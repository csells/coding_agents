import 'dart:async';

import '../cli_adapters/codex/codex.dart';
import 'coding_agent.dart';
import 'coding_agent_events.dart';
import 'coding_agent_types.dart';

/// Codex CLI implementation of CodingAgent
class CodexCodingAgent implements CodingAgent {
  final CodexCliAdapter _adapter = CodexCliAdapter();

  /// Approval policy for tool executions (when no approvalHandler is provided)
  final CodexApprovalPolicy approvalPolicy;

  /// Sandbox mode for file system access
  final CodexSandboxMode sandboxMode;

  /// Enable full auto mode (no approvals required)
  final bool fullAuto;

  /// Dangerously bypass all approvals and sandbox
  final bool dangerouslyBypassAll;

  /// Model to use (e.g., 'o3', 'o3-mini')
  final String? model;

  /// Enable web search capability
  final bool enableWebSearch;

  /// Environment variables to pass to the process
  final Map<String, String>? environment;

  /// Config overrides (key=value pairs passed via -c flag)
  final List<String>? configOverrides;

  CodexCodingAgent({
    this.approvalPolicy = CodexApprovalPolicy.onRequest,
    this.sandboxMode = CodexSandboxMode.workspaceWrite,
    this.fullAuto = false,
    this.dangerouslyBypassAll = false,
    this.model,
    this.enableWebSearch = false,
    this.environment,
    this.configOverrides,
  });

  CodexSessionConfig _buildConfig(ToolApprovalHandler? approvalHandler) =>
      CodexSessionConfig(
        approvalPolicy: approvalPolicy,
        sandboxMode: sandboxMode,
        approvalHandler: approvalHandler != null
            ? _wrapApprovalHandler(approvalHandler)
            : null,
        fullAuto: fullAuto,
        dangerouslyBypassAll: dangerouslyBypassAll,
        model: model,
        enableWebSearch: enableWebSearch,
        environment: environment,
        configOverrides: configOverrides,
      );

  /// Wrap unified ToolApprovalHandler as CodexApprovalHandler
  CodexApprovalHandler _wrapApprovalHandler(ToolApprovalHandler handler) {
    return (CodexApprovalRequest request) async {
      // Convert Codex request to unified request
      final unifiedRequest = ToolApprovalRequest(
        id: request.id,
        toolName: request.toolName ?? request.actionType,
        description: request.description,
        input: request.toolInput,
        command: request.command,
        filePath: request.filePath,
      );

      // Get unified response
      final unifiedResponse = await handler(unifiedRequest);

      // Convert to Codex response
      return CodexApprovalResponse(
        decision: switch (unifiedResponse.decision) {
          ToolApprovalDecision.allow => CodexApprovalDecision.allow,
          ToolApprovalDecision.deny => CodexApprovalDecision.deny,
          ToolApprovalDecision.allowAlways => CodexApprovalDecision.allowAlways,
          ToolApprovalDecision.denyAlways => CodexApprovalDecision.denyAlways,
        },
        message: unifiedResponse.message,
      );
    };
  }

  @override
  Future<CodingAgentSession> createSession({
    required String projectDirectory,
    ToolApprovalHandler? approvalHandler,
  }) async {
    return _CodexCodingAgentSession(
      adapter: _adapter,
      config: _buildConfig(approvalHandler),
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
    return _CodexCodingAgentSession(
      adapter: _adapter,
      config: _buildConfig(approvalHandler),
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
            sessionId: s.threadId,
            createdAt: s.timestamp,
            lastUpdatedAt: s.lastUpdated,
            projectDirectory: s.cwd,
            gitBranch: s.gitBranch,
          ),
        )
        .toList();
  }
}

class _CodexCodingAgentSession implements CodingAgentSession {
  final CodexCliAdapter _adapter;
  final CodexSessionConfig _config;
  final String _projectDirectory;
  final StreamController<CodingAgentEvent> _eventController =
      StreamController<CodingAgentEvent>.broadcast();

  String? _sessionId;
  int _turnCounter = 0;
  bool _turnInProgress = false;
  CodexSession? _currentUnderlyingSession;
  bool _sawPartialThisTurn = false;
  final Set<int> _agentMessageSeenTurns = {};

  _CodexCodingAgentSession({
    required CodexCliAdapter adapter,
    required CodexSessionConfig config,
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
    _sawPartialThisTurn = false;

    CodexSession underlyingSession;

    if (_sessionId == null) {
      // First turn - create new session
      underlyingSession = await _adapter.createSession(
        prompt,
        _config,
        projectDirectory: _projectDirectory,
      );
      _sessionId = underlyingSession.threadId;
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

    return _CodexCodingAgentTurn(
      turnId: turnId,
      underlyingSession: underlyingSession,
    );
  }

  void _transformAndEmit(CodexEvent event, int turnId) {
    final sid = _sessionId ?? event.threadId;

    switch (event) {
      case CodexThreadStartedEvent():
        _eventController.add(
          CodingAgentInitEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
          ),
        );

      case CodexSessionMetaEvent():
        // Session meta contains model info
        if (event.model != null) {
          _eventController.add(
            CodingAgentInitEvent(
              sessionId: sid,
              turnId: turnId,
              timestamp: event.timestamp,
              model: event.model,
            ),
          );
        }

      case CodexTurnStartedEvent():
        // Turn started is internal, no corresponding unified event needed
        break;

      case CodexAgentMessageEvent():
        if (event.isPartial) {
          _sawPartialThisTurn = true;
        } else if (_sawPartialThisTurn) {
          // Final full message after streaming deltas; already printed.
          break;
        }
        _agentMessageSeenTurns.add(turnId);
        _eventController.add(
          CodingAgentTextEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            text: event.message,
            isPartial: event.isPartial,
          ),
        );

      case CodexUserMessageEvent():
        // User messages are internal prompts, skip them
        break;

      case CodexItemStartedEvent():
        _emitItemEvent(event.item, sid, turnId, event.timestamp, isStart: true);

      case CodexItemUpdatedEvent():
        _emitItemEvent(
          event.item,
          sid,
          turnId,
          event.timestamp,
          isUpdate: true,
        );

      case CodexItemCompletedEvent():
        _emitItemEvent(
          event.item,
          sid,
          turnId,
          event.timestamp,
          isComplete: true,
          status: event.status,
        );

      case CodexTurnCompletedEvent():
        _sawPartialThisTurn = false;
        _agentMessageSeenTurns.remove(turnId);
        CodingAgentUsage? usage;
        if (event.usage != null) {
          usage = CodingAgentUsage(
            inputTokens: event.usage!.inputTokens,
            outputTokens: event.usage!.outputTokens,
            cachedInputTokens: event.usage!.cachedInputTokens,
          );
        }

        _eventController.add(
          CodingAgentTurnEndEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            status: CodingAgentTurnStatus.success,
            usage: usage,
          ),
        );

      case CodexTurnFailedEvent():
        _sawPartialThisTurn = false;
        _agentMessageSeenTurns.remove(turnId);
        _eventController.add(
          CodingAgentTurnEndEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            status: CodingAgentTurnStatus.error,
            errorMessage: event.message,
          ),
        );

      case CodexErrorEvent():
        _eventController.add(
          CodingAgentErrorEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            message: event.message,
          ),
        );

      case CodexApprovalRequiredEvent():
        // Approval is handled by the callback in the session,
        // but emit as unknown event for visibility
        _eventController.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'codex_approval_required',
            data: {
              'id': event.request.id,
              'action_type': event.request.actionType,
              'description': event.request.description,
            },
          ),
        );

      case CodexUnknownEvent():
        _eventController.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'codex_${event.type}',
            data: event.data,
          ),
        );
    }
  }

  void _emitItemEvent(
    CodexItem item,
    String sessionId,
    int turnId,
    DateTime timestamp, {
    bool isStart = false,
    bool isUpdate = false,
    bool isComplete = false,
    String? status,
  }) {
    switch (item) {
      case CodexAgentMessageItem():
        if (_agentMessageSeenTurns.contains(turnId)) {
          // Avoid duplicate text when both agent_message and agent_message_item arrive.
          return;
        }
        _eventController.add(
          CodingAgentTextEvent(
            sessionId: sessionId,
            turnId: turnId,
            timestamp: timestamp,
            text: item.text,
            isPartial: !isComplete,
          ),
        );

      case CodexReasoningItem():
        final thinking = item.reasoning ?? item.summary ?? '';
        if (thinking.isNotEmpty) {
          _eventController.add(
            CodingAgentThinkingEvent(
              sessionId: sessionId,
              turnId: turnId,
              timestamp: timestamp,
              thinking: thinking,
              summary: item.summary,
            ),
          );
        }

      case CodexToolCallItem():
        if (isStart || isUpdate) {
          // Emit tool use event when tool call starts
          _eventController.add(
            CodingAgentToolUseEvent(
              sessionId: sessionId,
              turnId: turnId,
              timestamp: timestamp,
              toolUseId: item.id,
              toolName: item.name,
              input: item.arguments,
            ),
          );
        }
        if (isComplete && item.output != null) {
          // Emit tool result when complete
          _eventController.add(
            CodingAgentToolResultEvent(
              sessionId: sessionId,
              turnId: turnId,
              timestamp: timestamp,
              toolUseId: item.id,
              output: item.output,
              isError: item.exitCode != null && item.exitCode != 0,
            ),
          );
        }

      case CodexFileChangeItem():
        // File changes are represented as tool results
        if (isComplete) {
          _eventController.add(
            CodingAgentToolResultEvent(
              sessionId: sessionId,
              turnId: turnId,
              timestamp: timestamp,
              toolUseId: item.id,
              output: item.diff ?? 'File changed: ${item.path}',
              isError: false,
            ),
          );
        }

      case CodexMcpToolCallItem():
        if (isStart || isUpdate) {
          _eventController.add(
            CodingAgentToolUseEvent(
              sessionId: sessionId,
              turnId: turnId,
              timestamp: timestamp,
              toolUseId: item.id,
              toolName: item.toolName,
              input: item.toolInput,
            ),
          );
        }
        if (isComplete && item.toolResult != null) {
          _eventController.add(
            CodingAgentToolResultEvent(
              sessionId: sessionId,
              turnId: turnId,
              timestamp: timestamp,
              toolUseId: item.id,
              output: item.toolResult.toString(),
              isError: false,
            ),
          );
        }

      case CodexWebSearchItem():
        if (isStart || isUpdate) {
          _eventController.add(
            CodingAgentToolUseEvent(
              sessionId: sessionId,
              turnId: turnId,
              timestamp: timestamp,
              toolUseId: item.id,
              toolName: 'web_search',
              input: {'query': item.query},
            ),
          );
        }
        if (isComplete) {
          _eventController.add(
            CodingAgentToolResultEvent(
              sessionId: sessionId,
              turnId: turnId,
              timestamp: timestamp,
              toolUseId: item.id,
              output: item.results.toString(),
              isError: false,
            ),
          );
        }

      case CodexTodoListItem():
        // Todo lists emitted as unknown events
        _eventController.add(
          CodingAgentUnknownEvent(
            sessionId: sessionId,
            turnId: turnId,
            timestamp: timestamp,
            originalType: 'codex_todo_list',
            data: {'id': item.id, 'items': item.items},
          ),
        );

      case CodexUnknownItem():
        _eventController.add(
          CodingAgentUnknownEvent(
            sessionId: sessionId,
            turnId: turnId,
            timestamp: timestamp,
            originalType: 'codex_unknown_item',
            data: item.data,
          ),
        );
    }
  }

  @override
  Future<List<CodingAgentEvent>> getHistory() async {
    if (_sessionId == null) {
      return [];
    }

    final codexEvents = await _adapter.getSessionHistory(
      _sessionId!,
      projectDirectory: _projectDirectory,
    );

    final events = <CodingAgentEvent>[];
    for (final event in codexEvents) {
      final transformed = _transformEventToList(event);
      events.addAll(transformed);
    }

    return events;
  }

  List<CodingAgentEvent> _transformEventToList(CodexEvent event) {
    final events = <CodingAgentEvent>[];
    final sid = _sessionId ?? event.threadId;
    final turnId = event.turnId;

    switch (event) {
      case CodexThreadStartedEvent():
        events.add(
          CodingAgentInitEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
          ),
        );

      case CodexSessionMetaEvent():
        if (event.model != null) {
          events.add(
            CodingAgentInitEvent(
              sessionId: sid,
              turnId: turnId,
              timestamp: event.timestamp,
              model: event.model,
            ),
          );
        }

      case CodexTurnStartedEvent():
        break;

      case CodexAgentMessageEvent():
        events.add(
          CodingAgentTextEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            text: event.message,
            isPartial: event.isPartial,
          ),
        );

      case CodexUserMessageEvent():
        break;

      case CodexItemStartedEvent():
        events.addAll(
          _transformItemToEvents(event.item, sid, turnId, event.timestamp),
        );

      case CodexItemUpdatedEvent():
        events.addAll(
          _transformItemToEvents(event.item, sid, turnId, event.timestamp),
        );

      case CodexItemCompletedEvent():
        events.addAll(
          _transformItemToEvents(
            event.item,
            sid,
            turnId,
            event.timestamp,
            isComplete: true,
          ),
        );

      case CodexTurnCompletedEvent():
        CodingAgentUsage? usage;
        if (event.usage != null) {
          usage = CodingAgentUsage(
            inputTokens: event.usage!.inputTokens,
            outputTokens: event.usage!.outputTokens,
            cachedInputTokens: event.usage!.cachedInputTokens,
          );
        }

        events.add(
          CodingAgentTurnEndEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            status: CodingAgentTurnStatus.success,
            usage: usage,
          ),
        );

      case CodexTurnFailedEvent():
        events.add(
          CodingAgentTurnEndEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            status: CodingAgentTurnStatus.error,
            errorMessage: event.message,
          ),
        );

      case CodexErrorEvent():
        events.add(
          CodingAgentErrorEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            message: event.message,
          ),
        );

      case CodexApprovalRequiredEvent():
        events.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'codex_approval_required',
            data: {
              'id': event.request.id,
              'action_type': event.request.actionType,
              'description': event.request.description,
            },
          ),
        );

      case CodexUnknownEvent():
        events.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'codex_${event.type}',
            data: event.data,
          ),
        );
    }

    return events;
  }

  List<CodingAgentEvent> _transformItemToEvents(
    CodexItem item,
    String sessionId,
    int turnId,
    DateTime timestamp, {
    bool isComplete = false,
  }) {
    final events = <CodingAgentEvent>[];

    switch (item) {
      case CodexAgentMessageItem():
        events.add(
          CodingAgentTextEvent(
            sessionId: sessionId,
            turnId: turnId,
            timestamp: timestamp,
            text: item.text,
            isPartial: !isComplete,
          ),
        );

      case CodexReasoningItem():
        final thinking = item.reasoning ?? item.summary ?? '';
        if (thinking.isNotEmpty) {
          events.add(
            CodingAgentThinkingEvent(
              sessionId: sessionId,
              turnId: turnId,
              timestamp: timestamp,
              thinking: thinking,
              summary: item.summary,
            ),
          );
        }

      case CodexToolCallItem():
        events.add(
          CodingAgentToolUseEvent(
            sessionId: sessionId,
            turnId: turnId,
            timestamp: timestamp,
            toolUseId: item.id,
            toolName: item.name,
            input: item.arguments,
          ),
        );
        if (isComplete && item.output != null) {
          events.add(
            CodingAgentToolResultEvent(
              sessionId: sessionId,
              turnId: turnId,
              timestamp: timestamp,
              toolUseId: item.id,
              output: item.output,
              isError: item.exitCode != null && item.exitCode != 0,
            ),
          );
        }

      case CodexFileChangeItem():
        if (isComplete) {
          events.add(
            CodingAgentToolResultEvent(
              sessionId: sessionId,
              turnId: turnId,
              timestamp: timestamp,
              toolUseId: item.id,
              output: item.diff ?? 'File changed: ${item.path}',
              isError: false,
            ),
          );
        }

      case CodexMcpToolCallItem():
        events.add(
          CodingAgentToolUseEvent(
            sessionId: sessionId,
            turnId: turnId,
            timestamp: timestamp,
            toolUseId: item.id,
            toolName: item.toolName,
            input: item.toolInput,
          ),
        );
        if (isComplete && item.toolResult != null) {
          events.add(
            CodingAgentToolResultEvent(
              sessionId: sessionId,
              turnId: turnId,
              timestamp: timestamp,
              toolUseId: item.id,
              output: item.toolResult.toString(),
              isError: false,
            ),
          );
        }

      case CodexWebSearchItem():
        events.add(
          CodingAgentToolUseEvent(
            sessionId: sessionId,
            turnId: turnId,
            timestamp: timestamp,
            toolUseId: item.id,
            toolName: 'web_search',
            input: {'query': item.query},
          ),
        );
        if (isComplete) {
          events.add(
            CodingAgentToolResultEvent(
              sessionId: sessionId,
              turnId: turnId,
              timestamp: timestamp,
              toolUseId: item.id,
              output: item.results.toString(),
              isError: false,
            ),
          );
        }

      case CodexTodoListItem():
        events.add(
          CodingAgentUnknownEvent(
            sessionId: sessionId,
            turnId: turnId,
            timestamp: timestamp,
            originalType: 'codex_todo_list',
            data: {'id': item.id, 'items': item.items},
          ),
        );

      case CodexUnknownItem():
        events.add(
          CodingAgentUnknownEvent(
            sessionId: sessionId,
            turnId: turnId,
            timestamp: timestamp,
            originalType: 'codex_unknown_item',
            data: item.data,
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

class _CodexCodingAgentTurn implements CodingAgentTurn {
  @override
  final int turnId;

  final CodexSession _underlyingSession;

  _CodexCodingAgentTurn({
    required this.turnId,
    required CodexSession underlyingSession,
  }) : _underlyingSession = underlyingSession;

  @override
  Future<void> cancel() async {
    await _underlyingSession.cancel();
  }
}
