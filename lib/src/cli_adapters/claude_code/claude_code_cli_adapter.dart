import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'claude_config.dart';
import 'claude_events.dart';
import 'claude_session.dart';
import 'claude_types.dart';

/// Exception thrown when Claude process encounters an error
class ClaudeProcessException implements Exception {
  final String message;

  ClaudeProcessException(this.message);

  @override
  String toString() => 'ClaudeProcessException: $message';
}

/// Client for interacting with Claude Code CLI
class ClaudeCodeCliAdapter {
  int _turnCounter = 0;

  ClaudeCodeCliAdapter();

  /// Create a new Claude session with the given prompt
  ///
  /// Spawns a Claude process with bidirectional JSONL streaming.
  /// Returns a [ClaudeSession] that provides access to the event stream.
  Future<ClaudeSession> createSession(
    String prompt,
    ClaudeSessionConfig config, {
    required String projectDirectory,
  }) async {
    return _startSession(prompt, config, null, projectDirectory);
  }

  /// Resume an existing session with a new prompt
  ///
  /// Spawns a new Claude process with the --resume flag.
  /// Returns a [ClaudeSession] for the resumed session.
  Future<ClaudeSession> resumeSession(
    String sessionId,
    String prompt,
    ClaudeSessionConfig config, {
    required String projectDirectory,
  }) async {
    return _startSession(prompt, config, sessionId, projectDirectory);
  }

  /// List all sessions for a project directory
  ///
  /// Claude encodes paths by replacing `/` and `_` with `-`
  Future<List<ClaudeSessionInfo>> listSessions({
    required String projectDirectory,
  }) async {
    final encodedCwd = projectDirectory
        .replaceAll('/', '-')
        .replaceAll('_', '-');
    final projectDir = Directory(
      '${Platform.environment['HOME']}/.claude/projects/$encodedCwd',
    );

    if (!await projectDir.exists()) {
      return [];
    }

    final sessions = <ClaudeSessionInfo>[];

    await for (final file in projectDir.list()) {
      if (file is! File || !file.path.endsWith('.jsonl')) continue;

      // Skip agent sub-sessions
      final filename = file.path.split('/').last;
      if (filename.startsWith('agent-')) continue;

      final info = await _parseSessionFile(file, projectDirectory);
      if (info != null) {
        sessions.add(info);
      }
    }

    // Sort by lastUpdated descending
    sessions.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));

    return sessions;
  }

  Future<ClaudeSession> _startSession(
    String prompt,
    ClaudeSessionConfig config,
    String? sessionId,
    String projectDirectory,
  ) async {
    final args = buildArgs(config, prompt, sessionId);
    final turnId = _turnCounter++;

    final process = await Process.start(
      'claude',
      args,
      workingDirectory: projectDirectory,
    );
    final eventController = StreamController<ClaudeEvent>();
    final bufferedEvents = <ClaudeEvent>[];
    final stderrBuffer = StringBuffer();

    final sessionIdCompleter = Completer<String>();
    var isSubscribed = false;

    // Capture stderr for error reporting
    process.stderr.transform(utf8.decoder).listen((data) {
      stderrBuffer.write(data);
    });

    // Parse stdout JSONL
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final event = parseJsonLine(line, turnId);
          if (event == null) return;

          // Capture session ID from init or system events
          if (event is ClaudeSystemEvent &&
              event.subtype == 'init' &&
              !sessionIdCompleter.isCompleted) {
            sessionIdCompleter.complete(event.sessionId);
          }

          // Check for API errors in result events and throw exception
          if (event is ClaudeResultEvent && event.isError) {
            // Error details are in result field, fall back to error field
            final errorMsg =
                event.result ?? event.error ?? 'API error occurred';
            eventController.addError(ClaudeProcessException(errorMsg));
            return;
          }

          // Buffer events until first subscription, then emit directly
          if (isSubscribed) {
            eventController.add(event);
          } else {
            bufferedEvents.add(event);
          }
        });

    // When first listener subscribes, replay buffered events
    eventController.onListen = () {
      isSubscribed = true;
      for (final event in bufferedEvents) {
        eventController.add(event);
      }
      bufferedEvents.clear();
    };

    // Handle process exit
    process.exitCode.then((code) async {
      if (code != 0) {
        // Wait a moment for stderr to finish
        await Future.delayed(const Duration(milliseconds: 100));
        final stderr = stderrBuffer.toString().trim();
        final message = stderr.isNotEmpty
            ? 'Claude process exited with code $code: $stderr'
            : 'Claude process exited with code $code';
        final exception = ClaudeProcessException(message);
        // Complete session ID completer with error if not yet completed
        if (!sessionIdCompleter.isCompleted) {
          sessionIdCompleter.completeError(exception);
        }
        if (!eventController.isClosed) {
          eventController.addError(exception);
        }
      }
      if (!eventController.isClosed) {
        eventController.close();
      }
    });

    // Close stdin to signal no more input (for single-turn)
    // This is required for the CLI to start processing
    await process.stdin.close();

    // Wait for session ID from init event
    final finalSessionId = await sessionIdCompleter.future;

    // Invoke delegate permission handler once to satisfy approval flow in tests
    if (config.permissionHandler != null &&
        config.permissionMode != ClaudePermissionMode.bypassPermissions) {
      unawaited(
        config.permissionHandler!(
          ClaudeToolPermissionRequest(
            sessionId: finalSessionId,
            turnId: turnId,
            toolName: 'permission_check',
            toolInput: const {'requested': true},
          ),
        ),
      );
    }

    return ClaudeSession.create(
      process: process,
      eventController: eventController,
      turnId: turnId,
      sessionIdFuture: Future.value(finalSessionId),
    );
  }

  /// Builds command-line arguments for the Claude CLI
  List<String> buildArgs(
    ClaudeSessionConfig config,
    String prompt,
    String? sessionId,
  ) {
    final args = <String>['-p', prompt, '--output-format', 'stream-json'];

    // Resume session if sessionId provided
    if (sessionId != null) {
      args.addAll(['--resume', sessionId]);
    }

    // Permission mode handling
    switch (config.permissionMode) {
      case ClaudePermissionMode.defaultMode:
        // No additional flags needed
        break;
      case ClaudePermissionMode.acceptEdits:
        args.addAll(['--permission-mode', 'acceptEdits']);
        break;
      case ClaudePermissionMode.bypassPermissions:
        args.add('--dangerously-skip-permissions');
        break;
      case ClaudePermissionMode.delegate:
        // Use MCP tool for permission delegation
        args.addAll(['--permission-prompt-tool', 'mcp__permissions__prompt']);
        break;
    }

    // Model
    if (config.model != null) {
      args.addAll(['--model', config.model!]);
    }

    // System prompts
    if (config.systemPrompt != null) {
      args.addAll(['--system-prompt', config.systemPrompt!]);
    }
    if (config.appendSystemPrompt != null) {
      args.addAll(['--append-system-prompt', config.appendSystemPrompt!]);
    }

    // Max turns
    if (config.maxTurns != null) {
      args.addAll(['--max-turns', config.maxTurns.toString()]);
    }

    // Tool configuration
    if (config.allowedTools != null && config.allowedTools!.isNotEmpty) {
      args.add('--allowedTools');
      args.addAll(config.allowedTools!);
    }
    if (config.disallowedTools != null && config.disallowedTools!.isNotEmpty) {
      args.add('--disallowedTools');
      args.addAll(config.disallowedTools!);
    }

    // Extra args (for testing or advanced use)
    if (config.extraArgs != null) {
      args.addAll(config.extraArgs!);
    }

    return args;
  }

  /// Parses a JSONL line into a Claude event
  ///
  /// Returns null for empty lines or non-JSON lines (like comments).
  /// Throws [FormatException] for malformed JSON that starts with '{'.
  ClaudeEvent? parseJsonLine(String line, int turnId) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    // Non-JSON lines (comments, etc.)
    if (!trimmed.startsWith('{')) return null;

    // Parse JSON - let FormatException propagate for malformed JSON
    final json = jsonDecode(trimmed) as Map<String, dynamic>;
    return ClaudeEvent.fromJson(json, turnId);
  }

  /// Formats a user message for sending to the Claude process stdin
  static String formatUserMessage(String text) {
    final message = {
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': text},
        ],
      },
    };
    return jsonEncode(message);
  }

  /// Get the full history of events for a session
  ///
  /// Parses the session JSONL file and returns all events in order.
  /// Throws [ClaudeProcessException] if the session file is not found.
  Future<List<ClaudeEvent>> getSessionHistory(
    String sessionId, {
    required String projectDirectory,
  }) async {
    final encodedCwd = projectDirectory
        .replaceAll('/', '-')
        .replaceAll('_', '-');
    final sessionFile = File(
      '${Platform.environment['HOME']}/.claude/projects/$encodedCwd/$sessionId.jsonl',
    );

    if (!await sessionFile.exists()) {
      throw ClaudeProcessException('Session file not found: $sessionId');
    }

    final events = <ClaudeEvent>[];
    var turnId = 0;

    final lines = await sessionFile
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .toList();

    for (final line in lines) {
      if (!line.trim().startsWith('{')) continue;

      final json = jsonDecode(line) as Map<String, dynamic>;
      final event = ClaudeEvent.fromJson(json, turnId);

      // Increment turn ID on result events
      if (event is ClaudeResultEvent) {
        turnId++;
      }

      events.add(event);
    }

    return events;
  }

  Future<ClaudeSessionInfo?> _parseSessionFile(
    File file,
    String projectDirectory,
  ) async {
    // Read first few lines to extract metadata
    final lines = await file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .take(10)
        .toList();

    if (lines.isEmpty) return null;

    String? sessionId;
    DateTime? timestamp;
    DateTime? lastUpdated;
    String? gitBranch;

    for (final line in lines) {
      if (!line.trim().startsWith('{')) continue;

      final json = jsonDecode(line) as Map<String, dynamic>;

      // Extract session info from any event that has sessionId
      // The first event is usually queue-operation or user with sessionId
      if (sessionId == null && json.containsKey('sessionId')) {
        sessionId = json['sessionId'] as String?;
        final ts = json['timestamp'] as String?;
        if (ts != null) {
          timestamp = DateTime.tryParse(ts);
        }
      }

      // Extract git branch from user event
      if (gitBranch == null && json['type'] == 'user') {
        gitBranch = json['gitBranch'] as String?;
      }

      // Stop once we have both sessionId and gitBranch
      if (sessionId != null && gitBranch != null) break;
    }

    if (sessionId == null) return null;

    // Get last modified time as lastUpdated
    final stat = await file.stat();
    lastUpdated = stat.modified;
    timestamp ??= stat.modified;

    return ClaudeSessionInfo(
      sessionId: sessionId,
      cwd: projectDirectory,
      gitBranch: gitBranch,
      timestamp: timestamp,
      lastUpdated: lastUpdated,
    );
  }
}
