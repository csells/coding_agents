import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../shared_utils.dart';
import 'claude_config.dart';
import 'claude_events.dart';
import 'claude_session.dart';
import 'claude_types.dart';

/// Exception thrown when Claude process encounters an error
class ClaudeProcessException extends CliProcessException {
  ClaudeProcessException(super.message);

  @override
  String get adapterName => 'ClaudeProcessException';
}

/// Client for interacting with Claude Code CLI
class ClaudeCodeCliAdapter {
  int _turnCounter = 0;

  ClaudeCodeCliAdapter();

  /// Create a new Claude session
  ///
  /// Spawns a Claude process with bidirectional JSONL streaming.
  /// Returns a [ClaudeSession] that provides access to the event stream.
  /// Call [ClaudeSession.send] to send the first prompt after subscribing
  /// to the event stream.
  Future<ClaudeSession> createSession(
    ClaudeSessionConfig config, {
    required String projectDirectory,
  }) async {
    return _startSession(config, null, projectDirectory);
  }

  /// Resume an existing session
  ///
  /// Spawns a new Claude process with the --resume flag.
  /// Returns a [ClaudeSession] for the resumed session.
  /// Call [ClaudeSession.send] to send the prompt after subscribing
  /// to the event stream.
  Future<ClaudeSession> resumeSession(
    String sessionId,
    ClaudeSessionConfig config, {
    required String projectDirectory,
  }) async {
    return _startSession(config, sessionId, projectDirectory);
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
    ClaudeSessionConfig config,
    String? sessionId,
    String projectDirectory,
  ) async {
    final args = buildArgs(config, sessionId);
    final turnId = _turnCounter++;

    final process = await Process.start(
      'claude',
      args,
      workingDirectory: projectDirectory,
    );
    final eventController = StreamController<ClaudeEvent>();
    final stderrBuffer = StringBuffer();

    // Create session immediately - session ID will be populated when init event arrives
    final session = ClaudeSession.create(
      process: process,
      eventController: eventController,
      turnId: turnId,
    );

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

          // Capture session ID from init event and update session
          if (event is ClaudeSystemEvent && event.subtype == 'init') {
            session.setSessionId(event.sessionId);
          }

          // Handle control_request events (permission prompts)
          if (event is ClaudeControlRequestEvent) {
            _handleControlRequest(session, event, config);
            // Also emit the event so clients can see permission requests
            eventController.add(event);
            return;
          }

          // Check for API errors in result events and throw exception
          if (event is ClaudeResultEvent && event.isError) {
            // Error details are in result field, fall back to error field
            final errorMsg =
                event.result ?? event.error ?? 'API error occurred';
            eventController.addError(ClaudeProcessException(errorMsg));
            return;
          }

          eventController.add(event);
        });

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
        // Deliver error through event stream (not sessionIdFuture to avoid unhandled errors)
        if (!eventController.isClosed) {
          eventController.addError(exception);
        }
      }
      if (!eventController.isClosed) {
        eventController.close();
      }
    });

    return session;
  }

  /// Builds command-line arguments for the Claude CLI
  List<String> buildArgs(
    ClaudeSessionConfig config,
    String? sessionId,
  ) {
    // Both flags required for bidirectional JSONL streaming
    final args = <String>[
      '--output-format',
      'stream-json',
      '--input-format',
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
        // Route permission prompts through stdio control channel
        args.addAll(['--permission-prompt-tool', 'stdio']);
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

  /// Handle a control_request event by calling the permission handler
  /// and sending back a control_response
  void _handleControlRequest(
    ClaudeSession session,
    ClaudeControlRequestEvent event,
    ClaudeSessionConfig config,
  ) {
    // Only handle can_use_tool requests
    if (event.subtype != 'can_use_tool') {
      return;
    }

    final handler = config.permissionHandler;
    if (handler == null) {
      // No handler - deny the request
      unawaited(
        session.sendControlResponse(
          event.requestId,
          ClaudeControlResponse.deny(
            message: 'No permission handler configured',
          ),
        ),
      );
      return;
    }

    // Call the permission handler asynchronously
    unawaited(
      handler(
        ClaudeToolPermissionRequest(
          sessionId: session.sessionId ?? '',
          turnId: event.turnId,
          toolName: event.toolName ?? 'unknown',
          toolInput: event.toolInput ?? const {},
          toolUseId: event.toolUseId,
          blockedPath: event.blockedPath,
          decisionReason: event.decisionReason,
        ),
      ).then((response) {
        final isAllowed = response.behavior == ClaudePermissionBehavior.allow ||
            response.behavior == ClaudePermissionBehavior.allowAlways;
        // For allow responses, updatedInput MUST contain the tool input.
        // If handler doesn't provide it, use the original input from the request.
        final controlResponse = isAllowed
            ? ClaudeControlResponse.allow(
                updatedInput: response.updatedInput ?? event.toolInput ?? const {},
              )
            : ClaudeControlResponse.deny(
                message: response.message ?? 'Denied by permission handler',
              );
        return session.sendControlResponse(event.requestId, controlResponse);
      }),
    );
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
