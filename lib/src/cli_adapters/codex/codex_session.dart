import 'dart:async';
import 'dart:io';

import 'codex_events.dart';

/// A Codex CLI session that manages process lifecycle and event streaming
///
/// Unlike Claude, Codex uses a process-per-turn model. Each send() spawns
/// a new process with the resume subcommand.
class CodexSession {
  /// Thread (session) identifier
  final String threadId;

  /// Stream of session events
  Stream<CodexEvent> get events => _eventController.stream;

  final StreamController<CodexEvent> _eventController;
  final int _currentTurnId;
  Process? _currentProcess;

  CodexSession._({
    required this.threadId,
    required StreamController<CodexEvent> eventController,
    required int turnId,
  }) : _eventController = eventController,
       _currentTurnId = turnId;

  /// Internal factory for creating sessions
  static Future<CodexSession> create({
    required StreamController<CodexEvent> eventController,
    required int turnId,
    required Future<String> threadIdFuture,
  }) async {
    final threadId = await threadIdFuture;
    return CodexSession._(
      threadId: threadId,
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
