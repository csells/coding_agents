import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'claude_events.dart';

/// Response to a control request for tool permission
class ClaudeControlResponse {
  /// Whether the tool use is allowed
  final bool allow;

  /// Message explaining the decision (required for deny)
  final String? message;

  /// Updated tool input (optional, only for allow)
  final Map<String, dynamic>? updatedInput;

  ClaudeControlResponse.allow({this.updatedInput}) : allow = true, message = null;

  ClaudeControlResponse.deny({required String this.message})
      : allow = false,
        updatedInput = null;
}

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
    // Close stdin first
    try {
      await _process.stdin.close();
    } on StateError {
      // Stdin already closed
    }

    // Send SIGINT to trigger clean exit - Claude CLI handles this gracefully
    // (equivalent to Ctrl+C in terminal)
    _process.kill(ProcessSignal.sigint);

    // Wait for the process to exit gracefully
    await _process.exitCode;
  }

  /// Send a control response back to Claude
  ///
  /// This is used to respond to control_request events (e.g., permission prompts).
  Future<void> sendControlResponse(
    String requestId,
    ClaudeControlResponse response,
  ) async {
    final responseData = <String, dynamic>{
      'behavior': response.allow ? 'allow' : 'deny',
    };

    if (response.allow) {
      // updatedInput is REQUIRED for allow responses (even if empty)
      responseData['updatedInput'] = response.updatedInput ?? <String, dynamic>{};
    } else {
      responseData['message'] = response.message ?? 'Denied by permission handler';
    }

    final message = {
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': requestId,
        'response': responseData,
      },
    };

    _process.stdin.writeln(jsonEncode(message));
    await _process.stdin.flush();
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
