import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'gemini_events.dart';
import 'gemini_types.dart';

/// Exception thrown when Gemini process encounters an error
class GeminiProcessException implements Exception {
  final String message;

  GeminiProcessException(this.message);

  @override
  String toString() => 'GeminiProcessException: $message';
}

/// A Gemini CLI session that manages process lifecycle and event streaming
///
/// Gemini uses a process-per-turn model. Each send() spawns a new process.
/// For subsequent turns, the process is spawned with the --resume flag.
class GeminiSession {
  /// Session identifier (null until first send completes)
  String? _sessionId;
  String? get sessionId => _sessionId;

  /// Stream of session events
  Stream<GeminiEvent> get events => _eventController.stream;

  final StreamController<GeminiEvent> _eventController;
  final GeminiSessionConfig _config;
  final String _projectDirectory;
  Process? _currentProcess;
  int _currentTurnId;
  bool _isFirstSend = true;

  GeminiSession._({
    required GeminiSessionConfig config,
    required String projectDirectory,
    required int turnId,
    String? sessionId,
  })  : _config = config,
        _projectDirectory = projectDirectory,
        _currentTurnId = turnId,
        _sessionId = sessionId,
        _eventController = StreamController<GeminiEvent>();

  /// Create a new session (no process started yet)
  static GeminiSession create({
    required GeminiSessionConfig config,
    required String projectDirectory,
    required int turnId,
  }) {
    return GeminiSession._(
      config: config,
      projectDirectory: projectDirectory,
      turnId: turnId,
    );
  }

  /// Create a session for resuming (sessionId already known)
  static GeminiSession createForResume({
    required String sessionId,
    required GeminiSessionConfig config,
    required String projectDirectory,
    required int turnId,
  }) {
    return GeminiSession._(
      config: config,
      projectDirectory: projectDirectory,
      turnId: turnId,
      sessionId: sessionId,
    );
  }

  /// Current turn ID
  int get currentTurnId => _currentTurnId;

  /// Send a prompt to the session
  ///
  /// Spawns a new Gemini process with the prompt. If this is a resumed
  /// session (sessionId is set), uses the --resume flag.
  /// Events will flow on the session's event stream.
  Future<void> send(String prompt) async {
    if (!_isFirstSend) {
      _currentTurnId++;
    }

    final args = _sessionId != null
        ? _buildResumeArgs(prompt)
        : _buildInitialArgs(prompt);

    final process = await Process.start(
      'gemini',
      args,
      workingDirectory: _projectDirectory,
    );
    _currentProcess = process;

    final stderrBuffer = StringBuffer();
    final sessionIdCompleter = Completer<String>();
    var capturedSessionId = _sessionId ?? '';

    // Capture stderr for error reporting
    process.stderr.transform(utf8.decoder).listen((data) {
      stderrBuffer.write(data);
    });

    // Parse stdout JSONL
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final event = _parseJsonLine(line, capturedSessionId, _currentTurnId);
          if (event == null) return;

          // Capture session ID from init event (first send only)
          if (event is GeminiInitEvent && _isFirstSend) {
            capturedSessionId = event.sessionId;
            _sessionId = event.sessionId;
            if (!sessionIdCompleter.isCompleted) {
              sessionIdCompleter.complete(event.sessionId);
            }
          }

          // Check for API errors in result events and throw exception
          if (event is GeminiResultEvent && event.status == 'error') {
            final errorMsg =
                event.error?['message'] as String? ??
                'Gemini API error occurred';
            _eventController.addError(GeminiProcessException(errorMsg));
            return;
          }

          _eventController.add(event);
        });

    // Handle process exit
    process.exitCode.then((code) async {
      if (code != 0 && !_eventController.isClosed) {
        // Wait a moment for stderr to finish
        await Future.delayed(const Duration(milliseconds: 100));
        final stderr = stderrBuffer.toString().trim();
        final message = stderr.isNotEmpty
            ? 'Gemini process exited with code $code: $stderr'
            : 'Gemini process exited with code $code';
        final exception = GeminiProcessException(message);
        if (_isFirstSend && !sessionIdCompleter.isCompleted) {
          sessionIdCompleter.completeError(exception);
        }
        _eventController.addError(exception);
      }
    });

    // Close stdin to signal no more input for this turn
    await process.stdin.close();

    // For first send, wait for session ID
    if (_isFirstSend) {
      await sessionIdCompleter.future;
      _isFirstSend = false;
    }
  }

  /// Cancel the current operation and close the session
  Future<void> cancel() async {
    _currentProcess?.kill(ProcessSignal.sigterm);
    await _eventController.close();
  }

  /// Builds command-line arguments for starting a new Gemini session
  List<String> _buildInitialArgs(String prompt) {
    // Gemini CLI uses positional prompt argument, not -p
    final args = <String>[prompt, '-o', 'stream-json'];

    _addConfigArgs(args);

    return args;
  }

  /// Builds command-line arguments for resuming a Gemini session
  List<String> _buildResumeArgs(String prompt) {
    // Gemini resume uses -r with actual session UUID and -p for the prompt
    final args = <String>['-p', prompt, '-o', 'stream-json', '-r', _sessionId!];

    _addConfigArgs(args);

    return args;
  }

  void _addConfigArgs(List<String> args) {
    // Approval mode
    switch (_config.approvalMode) {
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
    if (_config.sandbox) {
      args.add('--sandbox');
      if (_config.sandboxImage != null) {
        args.addAll(['--sandbox-image', _config.sandboxImage!]);
      }
    }

    // Model
    if (_config.model != null) {
      args.addAll(['--model', _config.model!]);
    }

    // Debug
    if (_config.debug) {
      args.add('--debug');
    }

    // Extra args (for testing or advanced use)
    if (_config.extraArgs != null) {
      args.addAll(_config.extraArgs!);
    }
  }

  /// Parses a JSONL line into a Gemini event
  GeminiEvent? _parseJsonLine(String line, String sessionId, int turnId) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    // Non-JSON lines (comments, etc.)
    if (!trimmed.startsWith('{')) return null;

    // Parse JSON - let FormatException propagate for malformed JSON
    final json = jsonDecode(trimmed) as Map<String, dynamic>;
    return GeminiEvent.fromJson(json, sessionId, turnId);
  }
}
