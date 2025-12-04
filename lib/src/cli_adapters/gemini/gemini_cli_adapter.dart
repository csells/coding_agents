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

    final sessionIdCompleter = Completer<String>();
    var isSubscribed = false;
    String sessionId = '';

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
          GeminiProcessException('Gemini process exited with code $code'),
        );
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

    var isSubscribed = false;

    // Parse stdout JSONL
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final event = parseJsonLine(line, sessionId, turnId);
          if (event == null) return;

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
          GeminiProcessException('Gemini process exited with code $code'),
        );
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
