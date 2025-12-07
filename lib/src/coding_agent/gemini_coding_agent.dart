import 'dart:async';

import '../cli_adapters/gemini/gemini.dart';
import 'coding_agent.dart';
import 'coding_agent_events.dart';
import 'coding_agent_types.dart';

/// Gemini CLI implementation of CodingAgent
class GeminiCodingAgent implements CodingAgent {
  final GeminiCliAdapter _adapter = GeminiCliAdapter();

  /// Approval mode for tool executions
  final GeminiApprovalMode approvalMode;

  /// Enable sandbox mode
  final bool sandbox;

  /// Custom sandbox Docker image
  final String? sandboxImage;

  /// Model to use (e.g., 'gemini-2.0-flash-exp')
  final String? model;

  /// Enable debug output
  final bool debug;

  GeminiCodingAgent({
    this.approvalMode = GeminiApprovalMode.defaultMode,
    this.sandbox = false,
    this.sandboxImage,
    this.model,
    this.debug = false,
  });

  GeminiSessionConfig _buildConfig() => GeminiSessionConfig(
    approvalMode: approvalMode,
    sandbox: sandbox,
    sandboxImage: sandboxImage,
    model: model,
    debug: debug,
  );

  @override
  Future<CodingAgentSession> createSession({
    required String projectDirectory,
    ToolApprovalHandler? approvalHandler,
  }) async {
    // Note: Gemini does not support interactive approval handling.
    // The approvalHandler parameter is ignored.
    return _GeminiCodingAgentSession(
      adapter: _adapter,
      config: _buildConfig(),
      projectDirectory: projectDirectory,
      existingSessionId: null,
    );
  }

  @override
  Future<CodingAgentSession> resumeSession(
    String sessionId, {
    required String projectDirectory,
    ToolApprovalHandler? approvalHandler,
  }) async {
    // Note: Gemini does not support interactive approval handling.
    // The approvalHandler parameter is ignored.
    return _GeminiCodingAgentSession(
      adapter: _adapter,
      config: _buildConfig(),
      projectDirectory: projectDirectory,
      existingSessionId: sessionId,
    );
  }

  @override
  Future<List<CodingAgentSessionInfo>> listSessions({
    required String projectDirectory,
  }) async {
    final sessions = await _adapter.listSessions(
      projectDirectory: projectDirectory,
    );
    return sessions
        .map(
          (s) => CodingAgentSessionInfo(
            sessionId: s.sessionId,
            createdAt: s.startTime,
            lastUpdatedAt: s.lastUpdated,
            messageCount: s.messageCount,
          ),
        )
        .toList();
  }
}

class _GeminiCodingAgentSession implements CodingAgentSession {
  final GeminiCliAdapter _adapter;
  final GeminiSessionConfig _config;
  final String _projectDirectory;
  final StreamController<CodingAgentEvent> _eventController =
      StreamController<CodingAgentEvent>.broadcast();

  String? _sessionId;
  int _turnCounter = 0;
  bool _turnInProgress = false;
  GeminiSession? _currentUnderlyingSession;

  _GeminiCodingAgentSession({
    required GeminiCliAdapter adapter,
    required GeminiSessionConfig config,
    required String projectDirectory,
    required String? existingSessionId,
  }) : _adapter = adapter,
       _config = config,
       _projectDirectory = projectDirectory,
       _sessionId = existingSessionId;

  @override
  String get sessionId => _sessionId ?? '';

  @override
  Stream<CodingAgentEvent> get events => _eventController.stream;

  @override
  Future<CodingAgentTurn> sendMessage(String prompt) async {
    if (_turnInProgress) {
      throw StateError('Cannot send message while turn is in progress');
    }

    _turnInProgress = true;
    final turnId = _turnCounter++;

    GeminiSession underlyingSession;

    if (_sessionId == null) {
      // First turn - create new session
      underlyingSession = await _adapter.createSession(
        prompt,
        _config,
        projectDirectory: _projectDirectory,
      );
      _sessionId = underlyingSession.sessionId;
    } else {
      // Subsequent turn - resume session
      underlyingSession = await _adapter.resumeSession(
        _sessionId!,
        prompt,
        _config,
        projectDirectory: _projectDirectory,
      );
    }

    _currentUnderlyingSession = underlyingSession;

    // Transform and forward events
    underlyingSession.events.listen(
      (event) => _transformAndEmit(event, turnId),
      onError: (Object e) {
        if (!_eventController.isClosed) {
          _eventController.addError(e);
        }
      },
      onDone: () {
        _turnInProgress = false;
        _currentUnderlyingSession = null;
      },
    );

    return _GeminiCodingAgentTurn(
      turnId: turnId,
      underlyingSession: underlyingSession,
    );
  }

  void _transformAndEmit(GeminiEvent event, int turnId) {
    final sid = _sessionId ?? event.sessionId;

    switch (event) {
      case GeminiInitEvent():
        _eventController.add(
          CodingAgentInitEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            model: event.model,
          ),
        );

      case GeminiMessageEvent():
        // Only emit assistant messages as text events
        if (event.role == 'assistant' || event.role == 'model') {
          _eventController.add(
            CodingAgentTextEvent(
              sessionId: sid,
              turnId: turnId,
              timestamp: event.timestamp,
              text: event.content,
              isPartial: event.delta,
            ),
          );
        }
        // Skip user messages (they're the prompts we sent)

      case GeminiToolUseEvent():
        _eventController.add(
          CodingAgentToolUseEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            toolUseId: event.toolUse.toolId,
            toolName: event.toolUse.toolName,
            input: event.toolUse.parameters,
          ),
        );

      case GeminiToolResultEvent():
        final isError =
            event.toolResult.status == 'error' || event.toolResult.error != null;
        _eventController.add(
          CodingAgentToolResultEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            toolUseId: event.toolResult.toolId,
            output: event.toolResult.output,
            isError: isError,
            errorMessage: isError ? event.toolResult.error?.toString() : null,
          ),
        );

      case GeminiResultEvent():
        final status = switch (event.status) {
          'success' => CodingAgentTurnStatus.success,
          'error' => CodingAgentTurnStatus.error,
          'cancelled' => CodingAgentTurnStatus.cancelled,
          _ => CodingAgentTurnStatus.success,
        };

        CodingAgentUsage? usage;
        if (event.stats != null) {
          usage = CodingAgentUsage(
            inputTokens: event.stats!.inputTokens,
            outputTokens: event.stats!.outputTokens,
          );
        }

        String? errorMessage;
        if (event.error != null) {
          errorMessage = event.error.toString();
        }

        _eventController.add(
          CodingAgentTurnEndEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            status: status,
            usage: usage,
            durationMs: event.stats?.durationMs,
            errorMessage: errorMessage,
          ),
        );

      case GeminiErrorEvent():
        _eventController.add(
          CodingAgentErrorEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            code: event.code,
            message: event.message,
          ),
        );

      case GeminiRetryEvent():
        // Retry events are transient, emit as unknown
        _eventController.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'gemini_retry',
            data: {
              'attempt': event.attempt,
              'max_attempts': event.maxAttempts,
              'delay_ms': event.delayMs,
            },
          ),
        );

      case GeminiUnknownEvent():
        _eventController.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'gemini_${event.type}',
            data: event.data,
          ),
        );
    }
  }

  @override
  Future<List<CodingAgentEvent>> getHistory() async {
    if (_sessionId == null) {
      return [];
    }

    final geminiEvents = await _adapter.getSessionHistory(
      _sessionId!,
      projectDirectory: _projectDirectory,
    );

    final events = <CodingAgentEvent>[];
    for (final event in geminiEvents) {
      final transformed = _transformEventToList(event);
      events.addAll(transformed);
    }

    return events;
  }

  List<CodingAgentEvent> _transformEventToList(GeminiEvent event) {
    final events = <CodingAgentEvent>[];
    final sid = _sessionId ?? event.sessionId;
    final turnId = event.turnId;

    switch (event) {
      case GeminiInitEvent():
        events.add(
          CodingAgentInitEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            model: event.model,
          ),
        );

      case GeminiMessageEvent():
        if (event.role == 'assistant' || event.role == 'model') {
          events.add(
            CodingAgentTextEvent(
              sessionId: sid,
              turnId: turnId,
              timestamp: event.timestamp,
              text: event.content,
              isPartial: event.delta,
            ),
          );
        }

      case GeminiToolUseEvent():
        events.add(
          CodingAgentToolUseEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            toolUseId: event.toolUse.toolId,
            toolName: event.toolUse.toolName,
            input: event.toolUse.parameters,
          ),
        );

      case GeminiToolResultEvent():
        final isError =
            event.toolResult.status == 'error' || event.toolResult.error != null;
        events.add(
          CodingAgentToolResultEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            toolUseId: event.toolResult.toolId,
            output: event.toolResult.output,
            isError: isError,
            errorMessage: isError ? event.toolResult.error?.toString() : null,
          ),
        );

      case GeminiResultEvent():
        final status = switch (event.status) {
          'success' => CodingAgentTurnStatus.success,
          'error' => CodingAgentTurnStatus.error,
          'cancelled' => CodingAgentTurnStatus.cancelled,
          _ => CodingAgentTurnStatus.success,
        };

        CodingAgentUsage? usage;
        if (event.stats != null) {
          usage = CodingAgentUsage(
            inputTokens: event.stats!.inputTokens,
            outputTokens: event.stats!.outputTokens,
          );
        }

        String? errorMessage;
        if (event.error != null) {
          errorMessage = event.error.toString();
        }

        events.add(
          CodingAgentTurnEndEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            status: status,
            usage: usage,
            durationMs: event.stats?.durationMs,
            errorMessage: errorMessage,
          ),
        );

      case GeminiErrorEvent():
        events.add(
          CodingAgentErrorEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            code: event.code,
            message: event.message,
          ),
        );

      case GeminiRetryEvent():
        events.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'gemini_retry',
            data: {
              'attempt': event.attempt,
              'max_attempts': event.maxAttempts,
              'delay_ms': event.delayMs,
            },
          ),
        );

      case GeminiUnknownEvent():
        events.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'gemini_${event.type}',
            data: event.data,
          ),
        );
    }

    return events;
  }

  @override
  Future<void> close() async {
    if (_currentUnderlyingSession != null) {
      await _currentUnderlyingSession!.cancel();
    }
    await _eventController.close();
  }
}

class _GeminiCodingAgentTurn implements CodingAgentTurn {
  @override
  final int turnId;

  final GeminiSession _underlyingSession;

  _GeminiCodingAgentTurn({
    required this.turnId,
    required GeminiSession underlyingSession,
  }) : _underlyingSession = underlyingSession;

  @override
  Future<void> cancel() async {
    await _underlyingSession.cancel();
  }
}
