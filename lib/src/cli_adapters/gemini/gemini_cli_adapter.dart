import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'gemini_events.dart';
import 'gemini_session.dart';
import 'gemini_types.dart';

/// Exception thrown when Gemini process encounters an error
class GeminiProcessException implements Exception {
  final String message;

  GeminiProcessException(this.message);

  @override
  String toString() => 'GeminiProcessException: $message';
}

/// Client for interacting with Gemini CLI
class GeminiCliAdapter {
  final String cwd;

  int _turnCounter = 0;

  GeminiCliAdapter({required this.cwd});

  /// List all sessions for this working directory
  ///
  /// Parses the text output from `gemini --list-sessions` which has format:
  /// ```
  /// Available sessions for this project (N):
  ///   1. Prompt text (time ago) [session-uuid]
  /// ```
  Future<List<GeminiSessionInfo>> listSessions() async {
    final result = await Process.run(
      'gemini',
      ['--list-sessions'],
      workingDirectory: cwd,
    );

    if (result.exitCode != 0) {
      throw GeminiProcessException('Failed to list sessions: ${result.stderr}');
    }

    // Gemini CLI writes list output to stderr
    final output = result.stderr as String;
    if (output.trim().isEmpty) return [];

    final sessions = <GeminiSessionInfo>[];
    final now = DateTime.now();

    // Pattern: "  1. Prompt text (time ago) [session-uuid]"
    final linePattern = RegExp(r'^\s*\d+\.\s+.+\s+\(([^)]+)\)\s+\[([a-f0-9-]+)\]$');

    for (final line in output.split('\n')) {
      final match = linePattern.firstMatch(line);
      if (match != null) {
        final timeAgo = match.group(1)!;
        final sessionId = match.group(2)!;

        // Parse relative time to approximate DateTime
        final timestamp = _parseRelativeTime(timeAgo, now);

        sessions.add(GeminiSessionInfo(
          sessionId: sessionId,
          projectHash: '', // Not available from CLI output
          startTime: timestamp,
          lastUpdated: timestamp,
          messageCount: 0, // Not available from CLI output
        ));
      }
    }

    return sessions;
  }

  /// Get the full history of events for a session
  ///
  /// Parses the session JSON file and returns all events in order.
  /// Gemini stores sessions as JSON files with a messages array.
  /// Throws [GeminiProcessException] if the session file is not found.
  Future<List<GeminiEvent>> getSessionHistory(String sessionId) async {
    final geminiDir = Directory(
      '${Platform.environment['HOME']}/.gemini/tmp',
    );

    if (!await geminiDir.exists()) {
      throw GeminiProcessException('Session not found: $sessionId');
    }

    // Find the session file by searching all project directories
    File? sessionFile;
    await for (final projectDir in geminiDir.list()) {
      if (projectDir is! Directory) continue;

      final chatsDir = Directory('${projectDir.path}/chats');
      if (!await chatsDir.exists()) continue;

      // Check all .json files in chats directory
      await for (final file in chatsDir.list()) {
        if (file is! File || !file.path.endsWith('.json')) continue;

        // Read file and check sessionId
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        if (json['sessionId'] == sessionId) {
          sessionFile = file;
          break;
        }
      }

      if (sessionFile != null) break;
    }

    if (sessionFile == null) {
      throw GeminiProcessException('Session not found: $sessionId');
    }

    // Parse the JSON file
    final content = await sessionFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final messages = json['messages'] as List<dynamic>? ?? [];

    final events = <GeminiEvent>[];
    var turnId = 0;

    // Add init event
    events.add(GeminiInitEvent(
      sessionId: sessionId,
      turnId: turnId,
      model: '',
    ));

    // Convert messages to events
    for (final msg in messages) {
      final msgMap = msg as Map<String, dynamic>;
      final type = msgMap['type'] as String?;
      final msgContent = msgMap['content'] as String? ?? '';
      final timestamp = DateTime.tryParse(msgMap['timestamp'] as String? ?? '');

      if (type == 'user') {
        events.add(GeminiMessageEvent(
          sessionId: sessionId,
          turnId: turnId,
          role: 'user',
          content: msgContent,
          delta: false,
          timestamp: timestamp,
        ));
      } else if (type == 'gemini') {
        events.add(GeminiMessageEvent(
          sessionId: sessionId,
          turnId: turnId,
          role: 'assistant',
          content: msgContent,
          delta: false,
          timestamp: timestamp,
        ));

        // Add a result event after assistant message to mark turn complete
        events.add(GeminiResultEvent(
          sessionId: sessionId,
          turnId: turnId,
          status: 'success',
          timestamp: timestamp,
        ));
        turnId++;
      }
    }

    return events;
  }

  /// Parse relative time strings like "1 hour ago", "Just now", "2 days ago"
  DateTime _parseRelativeTime(String timeAgo, DateTime now) {
    final lower = timeAgo.toLowerCase();

    if (lower == 'just now') {
      return now;
    }

    final pattern = RegExp(r'(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago');
    final match = pattern.firstMatch(lower);

    if (match != null) {
      final amount = int.parse(match.group(1)!);
      final unit = match.group(2)!;

      switch (unit) {
        case 'second':
          return now.subtract(Duration(seconds: amount));
        case 'minute':
          return now.subtract(Duration(minutes: amount));
        case 'hour':
          return now.subtract(Duration(hours: amount));
        case 'day':
          return now.subtract(Duration(days: amount));
        case 'week':
          return now.subtract(Duration(days: amount * 7));
        case 'month':
          return now.subtract(Duration(days: amount * 30));
        case 'year':
          return now.subtract(Duration(days: amount * 365));
      }
    }

    // Default to now if we can't parse
    return now;
  }

  /// Create a new Gemini session with the given prompt
  ///
  /// Spawns a Gemini process for the initial turn.
  /// Returns a [GeminiSession] that provides access to the event stream.
  Future<GeminiSession> createSession(
    String prompt,
    GeminiSessionConfig config,
  ) async {
    final args = buildInitialArgs(prompt, config);
    final turnId = _turnCounter++;

    final process = await Process.start('gemini', args, workingDirectory: cwd);
    final eventController = StreamController<GeminiEvent>();
    final bufferedEvents = <GeminiEvent>[];
    final stderrBuffer = StringBuffer();

    final sessionIdCompleter = Completer<String>();
    var isSubscribed = false;
    String sessionId = '';

    // Capture stderr for error reporting
    process.stderr.transform(utf8.decoder).listen((data) {
      stderrBuffer.write(data);
    });

    // Parse stdout JSONL
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final event = parseJsonLine(line, sessionId, turnId);
          if (event == null) return;

          // Capture session ID from init event
          if (event is GeminiInitEvent) {
            sessionId = event.sessionId;
            if (!sessionIdCompleter.isCompleted) {
              sessionIdCompleter.complete(event.sessionId);
            }
          }

          // Check for API errors in result events and throw exception
          if (event is GeminiResultEvent && event.status == 'error') {
            final errorMsg = event.error?['message'] as String? ??
                'Gemini API error occurred';
            eventController.addError(GeminiProcessException(errorMsg));
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
            ? 'Gemini process exited with code $code: $stderr'
            : 'Gemini process exited with code $code';
        final exception = GeminiProcessException(message);
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

    // Close stdin to signal no more input
    await process.stdin.close();

    // Wait for session ID from init event
    final finalSessionId = await sessionIdCompleter.future;

    final session = await GeminiSession.create(
      eventController: eventController,
      turnId: turnId,
      sessionIdFuture: Future.value(finalSessionId),
    );

    session.currentProcess = process;
    return session;
  }

  /// Resume an existing session with a new prompt
  ///
  /// Spawns a new Gemini process with the --resume flag using the actual
  /// session ID (UUID) from the original session's init event.
  /// Returns a [GeminiSession] for the resumed session.
  Future<GeminiSession> resumeSession(
    String sessionId,
    String prompt,
    GeminiSessionConfig config,
  ) async {
    final args = buildResumeArgs(sessionId, prompt, config);
    final turnId = _turnCounter++;

    final process = await Process.start('gemini', args, workingDirectory: cwd);
    final eventController = StreamController<GeminiEvent>();
    final bufferedEvents = <GeminiEvent>[];
    final stderrBuffer = StringBuffer();

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
          final event = parseJsonLine(line, sessionId, turnId);
          if (event == null) return;

          // Check for API errors in result events and throw exception
          if (event is GeminiResultEvent && event.status == 'error') {
            final errorMsg = event.error?['message'] as String? ??
                'Gemini API error occurred';
            eventController.addError(GeminiProcessException(errorMsg));
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
      if (code != 0 && !eventController.isClosed) {
        // Wait a moment for stderr to finish
        await Future.delayed(const Duration(milliseconds: 100));
        final stderr = stderrBuffer.toString().trim();
        final message = stderr.isNotEmpty
            ? 'Gemini process exited with code $code: $stderr'
            : 'Gemini process exited with code $code';
        eventController.addError(GeminiProcessException(message));
      }
      if (!eventController.isClosed) {
        eventController.close();
      }
    });

    // Close stdin to signal no more input
    await process.stdin.close();

    final session = await GeminiSession.create(
      eventController: eventController,
      turnId: turnId,
      sessionIdFuture: Future.value(sessionId),
    );

    session.currentProcess = process;
    return session;
  }

  /// Builds command-line arguments for starting a new Gemini session
  List<String> buildInitialArgs(String prompt, GeminiSessionConfig config) {
    // Gemini CLI uses positional prompt argument, not -p
    final args = <String>[prompt, '-o', 'stream-json'];

    // Approval mode
    switch (config.approvalMode) {
      case GeminiApprovalMode.defaultMode:
        // No additional flags
        break;
      case GeminiApprovalMode.autoEdit:
        args.add('--auto-edit');
        break;
      case GeminiApprovalMode.yolo:
        args.add('-y');
        break;
    }

    // Sandbox
    if (config.sandbox) {
      args.add('--sandbox');
      if (config.sandboxImage != null) {
        args.addAll(['--sandbox-image', config.sandboxImage!]);
      }
    }

    // Model
    if (config.model != null) {
      args.addAll(['--model', config.model!]);
    }

    // Debug
    if (config.debug) {
      args.add('--debug');
    }

    // Extra args (for testing or advanced use)
    if (config.extraArgs != null) {
      args.addAll(config.extraArgs!);
    }

    return args;
  }

  /// Builds command-line arguments for resuming a Gemini session
  List<String> buildResumeArgs(
    String sessionId,
    String prompt,
    GeminiSessionConfig config,
  ) {
    // Gemini resume uses -r with actual session UUID and -p for the prompt
    final args = <String>['-p', prompt, '-o', 'stream-json', '-r', sessionId];

    // Approval mode
    switch (config.approvalMode) {
      case GeminiApprovalMode.defaultMode:
        // No additional flags
        break;
      case GeminiApprovalMode.autoEdit:
        args.add('--auto-edit');
        break;
      case GeminiApprovalMode.yolo:
        args.add('-y');
        break;
    }

    // Sandbox
    if (config.sandbox) {
      args.add('--sandbox');
      if (config.sandboxImage != null) {
        args.addAll(['--sandbox-image', config.sandboxImage!]);
      }
    }

    // Model
    if (config.model != null) {
      args.addAll(['--model', config.model!]);
    }

    // Debug
    if (config.debug) {
      args.add('--debug');
    }

    // Extra args (for testing or advanced use)
    if (config.extraArgs != null) {
      args.addAll(config.extraArgs!);
    }

    return args;
  }

  /// Parses a JSONL line into a Gemini event
  ///
  /// Returns null for empty lines or non-JSON lines.
  /// Throws [FormatException] for malformed JSON that starts with '{'.
  GeminiEvent? parseJsonLine(String line, String sessionId, int turnId) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    // Non-JSON lines (comments, etc.)
    if (!trimmed.startsWith('{')) return null;

    // Parse JSON - let FormatException propagate for malformed JSON
    final json = jsonDecode(trimmed) as Map<String, dynamic>;
    return GeminiEvent.fromJson(json, sessionId, turnId);
  }
}
