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
class ClaudeClient {
  /// Working directory for the Claude process
  final String cwd;

  int _turnCounter = 0;

  ClaudeClient({required this.cwd});

  /// Create a new Claude session with the given prompt
  ///
  /// Spawns a Claude process with bidirectional JSONL streaming.
  /// Returns a [ClaudeSession] that provides access to the event stream.
  Future<ClaudeSession> createSession(
    String prompt,
    ClaudeSessionConfig config,
  ) async {
    return _startSession(prompt, config, null);
  }

  /// Resume an existing session with a new prompt
  ///
  /// Spawns a new Claude process with the --resume flag.
  /// Returns a [ClaudeSession] for the resumed session.
  Future<ClaudeSession> resumeSession(
    String sessionId,
    String prompt,
    ClaudeSessionConfig config,
  ) async {
    return _startSession(prompt, config, sessionId);
  }

  /// List all sessions for this working directory
  Future<List<ClaudeSessionInfo>> listSessions() async {
    final encodedCwd = cwd.replaceAll('/', '-');
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

      final info = await _parseSessionFile(file);
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
  ) async {
    final args = buildArgs(config, prompt, sessionId);
    final turnId = _turnCounter++;

    final process = await Process.start('claude', args, workingDirectory: cwd);
    final eventController = StreamController<ClaudeEvent>();
    final bufferedEvents = <ClaudeEvent>[];

    final sessionIdCompleter = Completer<String>();
    var isSubscribed = false;

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
    process.exitCode.then((code) {
      if (code != 0 && !eventController.isClosed) {
        eventController.addError(
          ClaudeProcessException('Claude process exited with code $code'),
        );
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
    final args = <String>[
      '-p',
      prompt,
      '--output-format',
      'stream-json',
    ];

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

  Future<ClaudeSessionInfo?> _parseSessionFile(File file) async {
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

      // Extract session info from system init event
      if (json['type'] == 'system' && json['subtype'] == 'init') {
        sessionId = json['session_id'] as String?;
        final ts = json['timestamp'] as String?;
        if (ts != null) {
          timestamp = DateTime.tryParse(ts);
        }
      }
    }

    if (sessionId == null) return null;

    // Get last modified time as lastUpdated
    final stat = await file.stat();
    lastUpdated = stat.modified;
    timestamp ??= stat.modified;

    return ClaudeSessionInfo(
      sessionId: sessionId,
      cwd: cwd,
      gitBranch: gitBranch,
      timestamp: timestamp,
      lastUpdated: lastUpdated,
    );
  }
}
