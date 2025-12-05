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

/// Client for interacting with Codex CLI
class CodexCliAdapter {
  /// Working directory for the Codex process
  final String cwd;

  int _turnCounter = 0;

  CodexCliAdapter({required this.cwd});

  /// List all sessions
  ///
  /// Codex stores sessions in `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
  Future<List<CodexSessionInfo>> listSessions() async {
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
      if (info != null) {
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
  /// Throws [CodexProcessException] if the session file is not found.
  Future<List<CodexEvent>> getSessionHistory(String threadId) async {
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
            sessionFile = entity;
            break;
          }
        }

        // Check thread.started event
        if (json['type'] == 'thread.started' &&
            json['thread_id'] == threadId) {
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

    final stat = await file.stat();
    final lastUpdated = stat.modified;
    timestamp ??= stat.modified;

    return CodexSessionInfo(
      threadId: threadId,
      timestamp: timestamp,
      lastUpdated: lastUpdated,
      cwd: sessionCwd ?? cwd,
      gitBranch: gitBranch,
    );
  }

  /// Create a new Codex session with the given prompt
  ///
  /// Spawns a Codex process for the initial turn.
  /// Returns a [CodexSession] that provides access to the event stream.
  Future<CodexSession> createSession(
    String prompt,
    CodexSessionConfig config,
  ) async {
    final args = buildInitialArgs(prompt, config);
    final turnId = _turnCounter++;

    final process = await Process.start('codex', args, workingDirectory: cwd);
    final eventController = StreamController<CodexEvent>();
    final bufferedEvents = <CodexEvent>[];
    final stderrBuffer = StringBuffer();
    String? lastErrorMessage;

    final threadIdCompleter = Completer<String>();
    var isSubscribed = false;
    String threadId = '';

    // Capture stderr for error reporting
    process.stderr.transform(utf8.decoder).listen((data) {
      stderrBuffer.write(data);
    });

    // Parse stdout JSONL
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final event = parseJsonLine(line, threadId, turnId);
          if (event == null) return;

          // Capture thread ID from thread.started event
          if (event is CodexThreadStartedEvent) {
            threadId = event.threadId;
            if (!threadIdCompleter.isCompleted) {
              threadIdCompleter.complete(event.threadId);
            }
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

    // Close stdin to signal no more input
    await process.stdin.close();

    // Wait for thread ID from thread.started event
    final finalThreadId = await threadIdCompleter.future;

    final session = await CodexSession.create(
      eventController: eventController,
      turnId: turnId,
      threadIdFuture: Future.value(finalThreadId),
    );

    session.currentProcess = process;
    return session;
  }

  /// Resume an existing session with a new prompt
  ///
  /// Spawns a new Codex process with the resume subcommand.
  /// Returns a [CodexSession] for the resumed session.
  Future<CodexSession> resumeSession(
    String threadId,
    String prompt,
    CodexSessionConfig config,
  ) async {
    final args = buildResumeArgs(prompt, threadId, config);
    final turnId = _turnCounter++;

    final process = await Process.start('codex', args, workingDirectory: cwd);
    final eventController = StreamController<CodexEvent>();
    final bufferedEvents = <CodexEvent>[];
    final stderrBuffer = StringBuffer();
    String? lastErrorMessage;

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
          final event = parseJsonLine(line, threadId, turnId);
          if (event == null) return;

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

    // Close stdin to signal no more input
    await process.stdin.close();

    final session = await CodexSession.create(
      eventController: eventController,
      turnId: turnId,
      threadIdFuture: Future.value(threadId),
    );

    session.currentProcess = process;
    return session;
  }

  /// Builds command-line arguments for starting a new Codex session
  List<String> buildInitialArgs(String prompt, CodexSessionConfig config) {
    final args = <String>['exec', '--json'];

    // Handle fullAuto mode - skips approval and sandbox args
    if (config.fullAuto) {
      args.add('--full-auto');
    } else {
      // Approval policy
      args.add('-a');
      args.add(formatEnumArg(config.approvalPolicy.name));

      // Sandbox mode
      args.add('-s');
      args.add(formatEnumArg(config.sandboxMode.name));
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

    // Prompt
    args.add(prompt);

    return args;
  }

  /// Builds command-line arguments for resuming a Codex session
  List<String> buildResumeArgs(
    String prompt,
    String threadId,
    CodexSessionConfig config,
  ) {
    final args = <String>['exec', '--json'];

    // Handle fullAuto mode
    if (config.fullAuto) {
      args.add('--full-auto');
    } else {
      // Approval policy
      args.add('-a');
      args.add(formatEnumArg(config.approvalPolicy.name));

      // Sandbox mode
      args.add('-s');
      args.add(formatEnumArg(config.sandboxMode.name));
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

    // Resume command with thread ID and prompt
    args.add('resume');
    args.add(threadId);
    args.add(prompt);

    return args;
  }

  /// Parses a JSONL line into a Codex event
  ///
  /// Returns null for empty lines or non-JSON lines.
  /// Throws [FormatException] for malformed JSON that starts with '{'.
  CodexEvent? parseJsonLine(String line, String threadId, int turnId) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    // Non-JSON lines (comments, etc.)
    if (!trimmed.startsWith('{')) return null;

    // Parse JSON - let FormatException propagate for malformed JSON
    final json = jsonDecode(trimmed) as Map<String, dynamic>;
    return CodexEvent.fromJson(json, threadId, turnId);
  }

  /// Converts camelCase enum name to kebab-case CLI argument
  String formatEnumArg(String enumName) {
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
