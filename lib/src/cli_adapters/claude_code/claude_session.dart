import 'dart:async';
import 'dart:io';

import 'claude_events.dart';

/// A Claude Code session that manages process lifecycle and event streaming
class ClaudeSession {
  /// Unique session identifier
  final String sessionId;

  /// Stream of session events
  Stream<ClaudeEvent> get events => _eventController.stream;

  final StreamController<ClaudeEvent> _eventController;
  final Process _process;
  final int _currentTurnId;

  ClaudeSession._({
    required this.sessionId,
    required StreamController<ClaudeEvent> eventController,
    required Process process,
    required int turnId,
  }) : _eventController = eventController,
       _process = process,
       _currentTurnId = turnId;

  /// Internal factory for creating sessions
  static Future<ClaudeSession> create({
    required Process process,
    required StreamController<ClaudeEvent> eventController,
    required int turnId,
    required Future<String> sessionIdFuture,
  }) async {
    final sessionId = await sessionIdFuture;
    return ClaudeSession._(
      sessionId: sessionId,
      eventController: eventController,
      process: process,
      turnId: turnId,
    );
  }

  /// Current turn ID
  int get currentTurnId => _currentTurnId;

  /// Cancel the current operation and close the session
  Future<void> cancel() async {
    _process.kill(ProcessSignal.sigterm);
    await _eventController.close();
  }
}
