import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'codex_config.dart';
import 'codex_events.dart';
import 'codex_types.dart';

/// A Codex CLI session using the app-server for long-lived connections
///
/// Unlike the process-per-turn exec mode, the app-server maintains a
/// persistent JSON-RPC connection for bidirectional communication.
class CodexSession {
  /// Thread (session) identifier
  final String threadId;

  /// Stream of session events
  Stream<CodexEvent> get events => _eventController.stream;

  final StreamController<CodexEvent> _eventController;
  final Process _process;
  final CodexApprovalHandler? _approvalHandler;
  final void Function(String prompt, String threadId)? _onSendPrompt;

  int _currentTurnId = 0;
  int _rpcId = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};
  bool _sentFirstMessage = false;
  Exception? _pendingError;

  CodexSession._({
    required this.threadId,
    required StreamController<CodexEvent> eventController,
    required Process process,
    CodexApprovalHandler? approvalHandler,
    void Function(String prompt, String threadId)? onSendPrompt,
    Exception? pendingError,
  })  : _eventController = eventController,
        _process = process,
        _approvalHandler = approvalHandler,
        _onSendPrompt = onSendPrompt,
        _pendingError = pendingError;

  /// Create a new session with an app-server process
  static Future<CodexSession> create({
    required Process process,
    required StreamController<CodexEvent> eventController,
    required Future<String> threadIdFuture,
    CodexApprovalHandler? approvalHandler,
    void Function(String prompt, String threadId)? onSendPrompt,
    Exception? pendingError,
  }) async {
    final threadId = await threadIdFuture;
    final session = CodexSession._(
      threadId: threadId,
      eventController: eventController,
      process: process,
      approvalHandler: approvalHandler,
      onSendPrompt: onSendPrompt,
      pendingError: pendingError,
    );
    return session;
  }

  /// Current turn ID
  int get currentTurnId => _currentTurnId;

  /// Increment the turn ID for a new turn
  void incrementTurnId() => _currentTurnId++;

  /// Send a message to the session
  ///
  /// For the first call, sends the initial prompt. For subsequent calls,
  /// increments the turn ID and sends a follow-up message.
  Future<void> send(String prompt) async {
    if (_pendingError != null) {
      throw _pendingError!;
    }

    // Increment turn ID for follow-up messages (not for the first message)
    if (_sentFirstMessage) {
      incrementTurnId();
    }
    _sentFirstMessage = true;

    _onSendPrompt?.call(prompt, threadId);

    final request = _buildRpcRequest('sendUserMessage', {
      'conversationId': threadId,
      'items': [
        {
          'type': 'text',
          'data': {'text': prompt},
        },
      ],
    });
    await _sendRpcRequest(request);
  }

  /// Respond to an approval request
  ///
  /// Send a decision for a pending approval request.
  Future<void> respondToApproval(
    String approvalId,
    CodexApprovalResponse response,
  ) async {
    final request = _buildRpcRequest('respondToApproval', {
      'approval_id': approvalId,
      'decision': _formatDecision(response.decision),
      if (response.message != null) 'message': response.message,
    });
    await _sendRpcRequest(request);
  }

  /// Cancel the current operation and close the session
  Future<void> cancel() async {
    // Send interrupt request if process stdin is still open
    final request = _buildRpcRequest('interrupt', {'thread_id': threadId});
    try {
      _writeToStdin(request);
    } on StateError {
      // Stdin already closed - process shutting down, continue with kill
    } on IOException {
      // I/O error writing to stdin - process likely dead, continue with kill
    }

    _process.kill(ProcessSignal.sigterm);
    await _eventController.close();
  }

  /// Build a JSON-RPC request
  Map<String, dynamic> _buildRpcRequest(
    String method,
    Map<String, dynamic> params,
  ) {
    return {
      'jsonrpc': '2.0',
      'id': ++_rpcId,
      'method': method,
      'params': params,
    };
  }

  /// Send a JSON-RPC request and wait for response
  Future<Map<String, dynamic>> _sendRpcRequest(
    Map<String, dynamic> request,
  ) async {
    final id = request['id'] as int;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    _writeToStdin(request);
    return completer.future;
  }

  /// Write a JSON message to stdin
  void _writeToStdin(Map<String, dynamic> message) {
    final json = jsonEncode(message);
    _process.stdin.writeln(json);
  }

  /// Handle a JSON-RPC response
  void handleRpcResponse(Map<String, dynamic> response) {
    final id = response['id'] as int?;
    if (id != null && _pendingRequests.containsKey(id)) {
      final completer = _pendingRequests.remove(id)!;
      if (response.containsKey('error')) {
        completer.completeError(
          CodexRpcException(response['error'] as Map<String, dynamic>),
        );
      } else {
        completer.complete(response['result'] as Map<String, dynamic>? ?? {});
      }
    }
  }

  /// Handle an approval request by invoking the callback
  ///
  /// If no approval handler is set, auto-deny the request to prevent
  /// tool execution in non-interactive mode.
  Future<void> handleApprovalRequest(CodexApprovalRequest request) async {
    if (_approvalHandler != null) {
      final response = await _approvalHandler(request);
      await respondToApproval(request.id, response);
    } else {
      // No handler - auto-deny to prevent tool execution
      await respondToApproval(
        request.id,
        CodexApprovalResponse(
          decision: CodexApprovalDecision.deny,
          message: 'Auto-denied: no approval handler configured',
        ),
      );
    }
  }

  void setPendingError(Exception exception) {
    _pendingError = exception;
    if (!_eventController.isClosed) {
      _eventController.addError(exception);
    }
  }

  /// Format a decision enum to string
  String _formatDecision(CodexApprovalDecision decision) {
    return switch (decision) {
      CodexApprovalDecision.allow => 'allow',
      CodexApprovalDecision.deny => 'deny',
      CodexApprovalDecision.allowAlways => 'allow_always',
      CodexApprovalDecision.denyAlways => 'deny_always',
    };
  }
}

/// Exception for JSON-RPC errors
class CodexRpcException implements Exception {
  final int code;
  final String message;
  final dynamic data;

  CodexRpcException(Map<String, dynamic> error)
      : code = error['code'] as int? ?? -1,
        message = error['message'] as String? ?? 'Unknown error',
        data = error['data'];

  @override
  String toString() => 'CodexRpcException: [$code] $message';
}
