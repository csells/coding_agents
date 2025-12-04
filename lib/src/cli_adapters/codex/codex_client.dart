import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'codex_config.dart';
import 'codex_events.dart';
import 'codex_session.dart';

/// Exception thrown when Codex process encounters an error
class CodexProcessException implements Exception {
  final String message;

  CodexProcessException(this.message);

  @override
  String toString() => 'CodexProcessException: $message';
}

/// Client for interacting with Codex CLI
class CodexClient {
  /// Working directory for the Codex process
  final String cwd;

  int _turnCounter = 0;

  CodexClient({required this.cwd});

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

    final threadIdCompleter = Completer<String>();
    var isSubscribed = false;
    String threadId = '';

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
          CodexProcessException('Codex process exited with code $code'),
        );
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

    var isSubscribed = false;

    // Parse stdout JSONL
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final event = parseJsonLine(line, threadId, turnId);
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
          CodexProcessException('Codex process exited with code $code'),
        );
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
