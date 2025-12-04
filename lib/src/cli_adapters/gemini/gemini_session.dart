import 'dart:async';
import 'dart:io';

import 'gemini_events.dart';

/// A Gemini CLI session that manages process lifecycle and event streaming
///
/// Like Codex, Gemini uses a process-per-turn model. Each send() spawns
/// a new process with the resume flag.
class GeminiSession {
  /// Session identifier
  final String sessionId;

  /// Stream of session events
  Stream<GeminiEvent> get events => _eventController.stream;

  final StreamController<GeminiEvent> _eventController;
  final int _currentTurnId;
  Process? _currentProcess;

  GeminiSession._({
    required this.sessionId,
    required StreamController<GeminiEvent> eventController,
    required int turnId,
  })  : _eventController = eventController,
        _currentTurnId = turnId;

  /// Internal factory for creating sessions
  static Future<GeminiSession> create({
    required StreamController<GeminiEvent> eventController,
    required int turnId,
    required Future<String> sessionIdFuture,
  }) async {
    final sessionId = await sessionIdFuture;
    return GeminiSession._(
      sessionId: sessionId,
      eventController: eventController,
      turnId: turnId,
    );
  }

  /// Current turn ID
  int get currentTurnId => _currentTurnId;

  /// Set the current process (used by client for process management)
  set currentProcess(Process? process) => _currentProcess = process;

  /// Cancel the current operation and close the session
  Future<void> cancel() async {
    _currentProcess?.kill(ProcessSignal.sigterm);
    await _eventController.close();
  }
}
