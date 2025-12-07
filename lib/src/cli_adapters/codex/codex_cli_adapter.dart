import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'codex_config.dart';
import 'codex_events.dart';
import 'codex_session.dart';
import 'codex_types.dart';

/// Exception thrown when Codex process encounters an error
class CodexProcessException implements Exception {
  final String message;

  CodexProcessException(this.message);

  @override
  String toString() => 'CodexProcessException: $message';
}

/// Client for interacting with Codex CLI via the app-server
///
/// Uses the `codex app-server` subcommand for long-lived JSON-RPC
/// communication, enabling:
/// - Multi-turn conversations within a single process
/// - Interactive approval handling via callbacks
/// - Bidirectional streaming
class CodexCliAdapter {
  CodexCliAdapter();

  /// List all sessions for a project directory
  ///
  /// Codex stores sessions in `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
  /// Only returns sessions that match the given projectDirectory.
  Future<List<CodexSessionInfo>> listSessions({
    required String projectDirectory,
  }) async {
    final sessionsDir = Directory(
      '${Platform.environment['HOME']}/.codex/sessions',
    );

    if (!await sessionsDir.exists()) {
      return [];
    }

    final sessions = <CodexSessionInfo>[];

    // Recursively search for .jsonl files
    await for (final entity in sessionsDir.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
      final info = await _parseSessionFile(entity);
      // Only include sessions that match this adapter's cwd
      if (info != null && info.cwd == projectDirectory) {
        sessions.add(info);
      }
    }

    // Sort by lastUpdated descending
    sessions.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    return sessions;
  }

  /// Get the full history of events for a session
  ///
  /// Parses the session JSONL file and returns all events in order.
  /// Only returns history for sessions that match the given projectDirectory.
  /// Throws [CodexProcessException] if the session file is not found.
  Future<List<CodexEvent>> getSessionHistory(
    String threadId, {
    required String projectDirectory,
  }) async {
    final sessionsDir = Directory(
      '${Platform.environment['HOME']}/.codex/sessions',
    );

    if (!await sessionsDir.exists()) {
      throw CodexProcessException('Session not found: $threadId');
    }

    // Find the session file containing this threadId
    File? sessionFile;
    await for (final entity in sessionsDir.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;

      // Check if this file contains our threadId
      final firstLines = await entity
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .take(10)
          .toList();

      for (final line in firstLines) {
        if (!line.trim().startsWith('{')) continue;
        final json = jsonDecode(line) as Map<String, dynamic>;

        // Check session_meta event
        if (json['type'] == 'session_meta') {
          final payload = json['payload'] as Map<String, dynamic>?;
          if (payload?['id'] == threadId) {
            // Verify session belongs to this projectDirectory
            final sessionCwd = payload?['cwd'] as String?;
            if (sessionCwd != projectDirectory) {
              throw CodexProcessException('Session not found: $threadId');
            }
            sessionFile = entity;
            break;
          }
        }

        // Check thread.started event
        if (json['type'] == 'thread.started' && json['thread_id'] == threadId) {
          sessionFile = entity;
          break;
        }
      }

      if (sessionFile != null) break;
    }

    if (sessionFile == null) {
      throw CodexProcessException('Session not found: $threadId');
    }

    final events = <CodexEvent>[];
    var turnId = 0;

    final lines = await sessionFile
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .toList();

    for (final line in lines) {
      if (!line.trim().startsWith('{')) continue;

      final json = jsonDecode(line) as Map<String, dynamic>;
      final event = CodexEvent.fromJson(json, threadId, turnId);

      // Increment turn ID on turn.completed events
      if (event is CodexTurnCompletedEvent) {
        turnId++;
      }

      events.add(event);
    }

    return events;
  }

  Future<CodexSessionInfo?> _parseSessionFile(File file) async {
    final lines = await file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .take(10)
        .toList();

    if (lines.isEmpty) return null;

    String? threadId;
    DateTime? timestamp;
    String? sessionCwd;
    String? gitBranch;

    for (final line in lines) {
      if (!line.trim().startsWith('{')) continue;
      final json = jsonDecode(line) as Map<String, dynamic>;

      // Extract session ID from session_meta event (new format)
      if (json['type'] == 'session_meta') {
        final payload = json['payload'] as Map<String, dynamic>?;
        if (payload != null) {
          threadId = payload['id'] as String?;
          sessionCwd = payload['cwd'] as String?;
          final ts = payload['timestamp'] as String?;
          if (ts != null) {
            timestamp = DateTime.tryParse(ts);
          }
          // Extract git branch if available
          final git = payload['git'] as Map<String, dynamic>?;
          if (git != null) {
            gitBranch = git['branch'] as String?;
          }
        }
        break;
      }

      // Fall back to thread.started event (legacy format)
      if (json['type'] == 'thread.started') {
        threadId = json['thread_id'] as String?;
        final ts = json['timestamp'] as String?;
        if (ts != null) {
          timestamp = DateTime.tryParse(ts);
        }
        break;
      }
    }

    if (threadId == null) return null;
    if (sessionCwd == null) return null; // Skip sessions without cwd metadata

    final stat = await file.stat();
    final lastUpdated = stat.modified;
    timestamp ??= stat.modified;

    return CodexSessionInfo(
      threadId: threadId,
      timestamp: timestamp,
      lastUpdated: lastUpdated,
      cwd: sessionCwd,
      gitBranch: gitBranch,
    );
  }

  /// Create a new Codex session with the given prompt
  ///
  /// Spawns the Codex app-server for long-lived JSON-RPC communication.
  /// Returns a [CodexSession] that provides access to the event stream.
  Future<CodexSession> createSession(
    String prompt,
    CodexSessionConfig config, {
    required String projectDirectory,
  }) async {
    final args = buildAppServerArgs(config);

    final process = await Process.start(
      'codex',
      args,
      workingDirectory: projectDirectory,
      environment: config.environment,
    );

    final eventController = StreamController<CodexEvent>();
    final bufferedEvents = <CodexEvent>[];
    final stderrBuffer = StringBuffer();
    String? lastErrorMessage;

    final threadIdCompleter = Completer<String>();
    var isSubscribed = false;
    String threadId = '';
    CodexSession? session;

    // Capture stderr for error reporting
    process.stderr.transform(utf8.decoder).listen((data) {
      stderrBuffer.write(data);
    });

    // Parse stdout JSONL (JSON-RPC messages and notifications)
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final parsed = _parseJsonLine(line, threadId);
      if (parsed == null) return;

      // Handle JSON-RPC responses
      if (parsed['jsonrpc'] == '2.0' && parsed.containsKey('id')) {
        session?.handleRpcResponse(parsed);
        return;
      }

      // Convert to event
      final event = CodexEvent.fromJson(
        parsed,
        threadId,
        session?.currentTurnId ?? 0,
      );

      // Capture thread ID from thread.started event
      if (event is CodexThreadStartedEvent) {
        threadId = event.threadId;
        if (!threadIdCompleter.isCompleted) {
          threadIdCompleter.complete(event.threadId);
        }
      }

      // Handle approval requests via callback
      if (event is CodexApprovalRequiredEvent) {
        session?.handleApprovalRequest(event.request);
      }

      // Capture error messages from error events
      if (event is CodexErrorEvent) {
        lastErrorMessage = event.message;
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
        // Prefer error from JSONL events, fall back to stderr
        final errorDetail = lastErrorMessage ?? stderr;
        final message = errorDetail.isNotEmpty
            ? 'Codex process exited with code $code: $errorDetail'
            : 'Codex process exited with code $code';
        final exception = CodexProcessException(message);
        // Complete thread ID completer with error if not yet completed
        if (!threadIdCompleter.isCompleted) {
          threadIdCompleter.completeError(exception);
        }
        if (!eventController.isClosed) {
          eventController.addError(exception);
        }
      }
      if (!eventController.isClosed) {
        eventController.close();
      }
    });

    // Send initial createThread request with the prompt
    final createRequest = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'createThread',
      'params': {
        'message': prompt,
        'cwd': projectDirectory,
      },
    };
    process.stdin.writeln(jsonEncode(createRequest));

    // Wait for thread ID from thread.started event
    final finalThreadId = await threadIdCompleter.future;

    session = await CodexSession.create(
      process: process,
      eventController: eventController,
      threadIdFuture: Future.value(finalThreadId),
      approvalHandler: config.approvalHandler,
    );

    return session;
  }

  /// Resume an existing session with a new prompt
  ///
  /// Spawns a new app-server process and resumes the session.
  /// Returns a [CodexSession] for the resumed session.
  Future<CodexSession> resumeSession(
    String threadId,
    String prompt,
    CodexSessionConfig config, {
    required String projectDirectory,
  }) async {
    final args = buildAppServerArgs(config);

    final process = await Process.start(
      'codex',
      args,
      workingDirectory: projectDirectory,
      environment: config.environment,
    );

    final eventController = StreamController<CodexEvent>();
    final bufferedEvents = <CodexEvent>[];
    final stderrBuffer = StringBuffer();
    String? lastErrorMessage;

    var isSubscribed = false;
    CodexSession? session;

    // Capture stderr for error reporting
    process.stderr.transform(utf8.decoder).listen((data) {
      stderrBuffer.write(data);
    });

    // Parse stdout JSONL
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final parsed = _parseJsonLine(line, threadId);
      if (parsed == null) return;

      // Handle JSON-RPC responses
      if (parsed['jsonrpc'] == '2.0' && parsed.containsKey('id')) {
        session?.handleRpcResponse(parsed);
        return;
      }

      // Convert to event
      final event = CodexEvent.fromJson(
        parsed,
        threadId,
        session?.currentTurnId ?? 0,
      );

      // Handle approval requests via callback
      if (event is CodexApprovalRequiredEvent) {
        session?.handleApprovalRequest(event.request);
      }

      // Capture error messages from error events
      if (event is CodexErrorEvent) {
        lastErrorMessage = event.message;
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
      if (code != 0 && !eventController.isClosed) {
        // Wait a moment for stderr to finish
        await Future.delayed(const Duration(milliseconds: 100));
        final stderr = stderrBuffer.toString().trim();
        // Prefer error from JSONL events, fall back to stderr
        final errorDetail = lastErrorMessage ?? stderr;
        final message = errorDetail.isNotEmpty
            ? 'Codex process exited with code $code: $errorDetail'
            : 'Codex process exited with code $code';
        eventController.addError(CodexProcessException(message));
      }
      if (!eventController.isClosed) {
        eventController.close();
      }
    });

    // Send resumeThread request with the prompt
    final resumeRequest = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'resumeThread',
      'params': {
        'thread_id': threadId,
        'message': prompt,
      },
    };
    process.stdin.writeln(jsonEncode(resumeRequest));

    session = await CodexSession.create(
      process: process,
      eventController: eventController,
      threadIdFuture: Future.value(threadId),
      approvalHandler: config.approvalHandler,
    );

    return session;
  }

  /// Builds command-line arguments for the app-server
  List<String> buildAppServerArgs(CodexSessionConfig config) {
    final args = <String>['app-server'];

    // Handle fullAuto mode - skips approval and sandbox args
    if (config.fullAuto) {
      args.add('--full-auto');
    } else {
      // Approval policy
      args.add('-a');
      args.add(_formatEnumArg(config.approvalPolicy.name));

      // Sandbox mode
      args.add('-s');
      args.add(_formatEnumArg(config.sandboxMode.name));
    }

    // Dangerous bypass
    if (config.dangerouslyBypassAll) {
      args.add('--dangerously-bypass-approvals-and-sandbox');
    }

    // Model
    if (config.model != null) {
      args.add('-m');
      args.add(config.model!);
    }

    // Web search
    if (config.enableWebSearch) {
      args.add('--search');
    }

    // Config overrides
    if (config.configOverrides != null) {
      for (final override in config.configOverrides!) {
        args.add('-c');
        args.add(override);
      }
    }

    // Extra args (for testing or advanced use)
    if (config.extraArgs != null) {
      args.addAll(config.extraArgs!);
    }

    return args;
  }

  /// Parses a JSONL line into a JSON map
  ///
  /// Returns null for empty lines or non-JSON lines.
  /// Throws [FormatException] for malformed JSON that starts with '{'.
  Map<String, dynamic>? _parseJsonLine(String line, String threadId) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    // Non-JSON lines (comments, etc.)
    if (!trimmed.startsWith('{')) return null;

    // Parse JSON - let FormatException propagate for malformed JSON
    return jsonDecode(trimmed) as Map<String, dynamic>;
  }

  /// Converts camelCase enum name to kebab-case CLI argument
  String _formatEnumArg(String enumName) {
    final buffer = StringBuffer();
    for (var i = 0; i < enumName.length; i++) {
      final char = enumName[i];
      if (char.toUpperCase() == char && char.toLowerCase() != char) {
        if (buffer.isNotEmpty) {
          buffer.write('-');
        }
        buffer.write(char.toLowerCase());
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }
}
