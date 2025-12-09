import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'claude_events.dart';

/// A Claude Code session that manages process lifecycle and event streaming
class ClaudeSession {
  /// Unique session identifier
  ///
  /// This is null until the first prompt is sent and the init event is received.
  String? get sessionId => _sessionId;
  String? _sessionId;

  /// Stream of session events
  Stream<ClaudeEvent> get events => _eventController.stream;

  final StreamController<ClaudeEvent> _eventController;
  final Process _process;
  final int _currentTurnId;

  ClaudeSession._({
    required StreamController<ClaudeEvent> eventController,
    required Process process,
    required int turnId,
  })  : _eventController = eventController,
        _process = process,
        _currentTurnId = turnId;

  /// Internal factory for creating sessions
  ///
  /// The session is returned immediately. The session ID will be populated
  /// when the init event is received (after the first prompt is sent).
  static ClaudeSession create({
    required Process process,
    required StreamController<ClaudeEvent> eventController,
    required int turnId,
  }) {
    return ClaudeSession._(
      eventController: eventController,
      process: process,
      turnId: turnId,
    );
  }

  /// Set the session ID (called when init event is received)
  void setSessionId(String id) {
    _sessionId = id;
  }

  /// Current turn ID
  int get currentTurnId => _currentTurnId;

  /// Send a prompt to the session
  ///
  /// Writes the prompt to the process stdin as a user message.
  /// Events will flow on the session's event stream.
  Future<void> send(String prompt) async {
    final message = formatUserMessage(prompt);
    _process.stdin.writeln(message);
    await _process.stdin.flush();
    // Note: turnId is managed by the adapter, not incremented here
  }

  /// Cancel the current operation and close the session
  Future<void> cancel() async {
    _process.kill(ProcessSignal.sigterm);
    await _eventController.close();
  }

  /// Formats a user message for sending to the Claude process stdin
  ///
  /// Format: {"type":"user","message":{"role":"user","content":[{"type":"text","text":"..."}]}}
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
}
