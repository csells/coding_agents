import 'dart:async';

import '../cli_adapters/claude_code/claude_code.dart';
import 'coding_agent.dart';
import 'coding_agent_events.dart';
import 'coding_agent_types.dart';

/// Claude Code implementation of CodingAgent
class ClaudeCodingAgent implements CodingAgent {
  final ClaudeCodeCliAdapter _adapter = ClaudeCodeCliAdapter();

  /// Permission mode for tool execution (when no approvalHandler is provided)
  ///
  /// If an [approvalHandler] is passed to [createSession]/[resumeSession],
  /// the permission mode will be set to [ClaudePermissionMode.delegate].
  final ClaudePermissionMode permissionMode;

  /// Model to use (e.g., 'claude-sonnet-4-5-20250929')
  final String? model;

  /// Custom system prompt (replaces default)
  final String? systemPrompt;

  /// Additional system prompt (appended to default)
  final String? appendSystemPrompt;

  /// Maximum number of turns before stopping
  final int? maxTurns;

  /// List of tools to allow (if specified, only these tools are available)
  final List<String>? allowedTools;

  /// List of tools to disallow
  final List<String>? disallowedTools;

  ClaudeCodingAgent({
    this.permissionMode = ClaudePermissionMode.defaultMode,
    this.model,
    this.systemPrompt,
    this.appendSystemPrompt,
    this.maxTurns,
    this.allowedTools,
    this.disallowedTools,
  });

  ClaudeSessionConfig _buildConfig(ToolApprovalHandler? approvalHandler) {
    // If an approval handler is provided, use delegate mode with adapter
    if (approvalHandler != null) {
      return ClaudeSessionConfig(
        permissionMode: ClaudePermissionMode.delegate,
        permissionHandler: _wrapApprovalHandler(approvalHandler),
        model: model,
        systemPrompt: systemPrompt,
        appendSystemPrompt: appendSystemPrompt,
        maxTurns: maxTurns,
        allowedTools: allowedTools,
        disallowedTools: disallowedTools,
      );
    }

    return ClaudeSessionConfig(
      permissionMode: permissionMode,
      model: model,
      systemPrompt: systemPrompt,
      appendSystemPrompt: appendSystemPrompt,
      maxTurns: maxTurns,
      allowedTools: allowedTools,
      disallowedTools: disallowedTools,
    );
  }

  /// Wrap unified ToolApprovalHandler as ClaudePermissionHandler
  ClaudePermissionHandler _wrapApprovalHandler(ToolApprovalHandler handler) {
    return (ClaudeToolPermissionRequest request) async {
      // Convert Claude request to unified request
      final unifiedRequest = ToolApprovalRequest(
        id: '${request.sessionId}_${request.turnId}_${request.toolName}',
        toolName: request.toolName,
        description: 'Tool: ${request.toolName}',
        input: request.toolInput,
        command: request.toolInput['command'] as String?,
        filePath: request.toolInput['file_path'] as String? ??
            request.toolInput['path'] as String?,
      );

      // Get unified response
      final unifiedResponse = await handler(unifiedRequest);

      // Convert to Claude response
      return ClaudeToolPermissionResponse(
        behavior: switch (unifiedResponse.decision) {
          ToolApprovalDecision.allow => ClaudePermissionBehavior.allow,
          ToolApprovalDecision.deny => ClaudePermissionBehavior.deny,
          ToolApprovalDecision.allowAlways => ClaudePermissionBehavior.allowAlways,
          ToolApprovalDecision.denyAlways => ClaudePermissionBehavior.denyAlways,
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
    return _ClaudeCodingAgentSession(
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
    return _ClaudeCodingAgentSession(
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
            sessionId: s.sessionId,
            createdAt: s.timestamp,
            lastUpdatedAt: s.lastUpdated,
            projectDirectory: s.cwd,
            gitBranch: s.gitBranch,
          ),
        )
        .toList();
  }
}

class _ClaudeCodingAgentSession implements CodingAgentSession {
  final ClaudeCodeCliAdapter _adapter;
  final ClaudeSessionConfig _config;
  final String _projectDirectory;
  final StreamController<CodingAgentEvent> _eventController =
      StreamController<CodingAgentEvent>.broadcast();

  String? _sessionId;
  int _turnCounter = 0;
  bool _turnInProgress = false;
  ClaudeSession? _currentUnderlyingSession;

  _ClaudeCodingAgentSession({
    required ClaudeCodeCliAdapter adapter,
    required ClaudeSessionConfig config,
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

    ClaudeSession underlyingSession;

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

    return _ClaudeCodingAgentTurn(
      turnId: turnId,
      underlyingSession: underlyingSession,
    );
  }

  void _transformAndEmit(ClaudeEvent event, int turnId) {
    final sid = _sessionId ?? event.sessionId;

    switch (event) {
      case ClaudeInitEvent():
        _eventController.add(
          CodingAgentInitEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            model: event.model,
          ),
        );

      case ClaudeAssistantEvent():
        // Iterate through content blocks and emit separate events
        for (final block in event.content) {
          switch (block) {
            case ClaudeTextBlock():
              _eventController.add(
                CodingAgentTextEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  text: block.text,
                  isPartial: false,
                ),
              );
            case ClaudeThinkingBlock():
              _eventController.add(
                CodingAgentThinkingEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  thinking: block.thinking,
                ),
              );
            case ClaudeToolUseBlock():
              _eventController.add(
                CodingAgentToolUseEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  toolUseId: block.id,
                  toolName: block.name,
                  input: block.input,
                ),
              );
            case ClaudeToolResultBlock():
              // Tool results in assistant events are unusual but handle them
              _eventController.add(
                CodingAgentToolResultEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  toolUseId: block.toolUseId,
                  output: block.content,
                  isError: block.isError ?? false,
                ),
              );
            case ClaudeUnknownBlock():
              _eventController.add(
                CodingAgentUnknownEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  originalType: 'claude_block_${block.type}',
                  data: block.data,
                ),
              );
          }
        }

      case ClaudeUserEvent():
        // User events typically contain tool results
        for (final block in event.content) {
          switch (block) {
            case ClaudeToolResultBlock():
              _eventController.add(
                CodingAgentToolResultEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  toolUseId: block.toolUseId,
                  output: block.content,
                  isError: block.isError ?? false,
                ),
              );
            case ClaudeTextBlock():
              // User text blocks are typically tool results displayed as text
              _eventController.add(
                CodingAgentTextEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  text: block.text,
                  isPartial: false,
                ),
              );
            case ClaudeThinkingBlock():
            case ClaudeToolUseBlock():
            case ClaudeUnknownBlock():
              // These are unusual in user events, skip them
              break;
          }
        }

      case ClaudeResultEvent():
        final status = switch (event.subtype) {
          'success' => CodingAgentTurnStatus.success,
          'error' => CodingAgentTurnStatus.error,
          'cancelled' => CodingAgentTurnStatus.cancelled,
          _ => CodingAgentTurnStatus.success,
        };

        CodingAgentUsage? usage;
        if (event.usage != null) {
          usage = CodingAgentUsage(
            inputTokens: event.usage!.inputTokens,
            outputTokens: event.usage!.outputTokens,
            cacheCreationInputTokens: event.usage!.cacheCreationInputTokens,
            cacheReadInputTokens: event.usage!.cacheReadInputTokens,
          );
        }

        _eventController.add(
          CodingAgentTurnEndEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            status: status,
            usage: usage,
            durationMs: event.durationMs,
            errorMessage: event.isError ? (event.result ?? event.error) : null,
          ),
        );

      case ClaudeSystemEvent():
        // System events are mostly internal (init, compact_boundary)
        // Emit as unknown for transparency
        _eventController.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'claude_system_${event.subtype}',
            data: event.data,
          ),
        );

      case ClaudeToolProgressEvent():
        // Tool progress events are informational - emit as unknown
        _eventController.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'claude_tool_progress',
            data: {
              'tool_use_id': event.toolUseId,
              'tool_name': event.toolName,
              'elapsed_time_seconds': event.elapsedTimeSeconds,
              'parent_tool_use_id': event.parentToolUseId,
            },
          ),
        );

      case ClaudeAuthStatusEvent():
        // Auth status events are informational - emit as unknown
        _eventController.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'claude_auth_status',
            data: {
              'isAuthenticating': event.isAuthenticating,
              'output': event.output,
              'error': event.error,
            },
          ),
        );

      case ClaudeUnknownEvent():
        _eventController.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'claude_${event.type}',
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

    final claudeEvents = await _adapter.getSessionHistory(
      _sessionId!,
      projectDirectory: _projectDirectory,
    );

    final events = <CodingAgentEvent>[];
    for (final event in claudeEvents) {
      // We need to transform each event, reusing the transform logic
      // but collecting into a list instead of streaming
      final transformed = _transformEventToList(event);
      events.addAll(transformed);
    }

    return events;
  }

  List<CodingAgentEvent> _transformEventToList(ClaudeEvent event) {
    final events = <CodingAgentEvent>[];
    final sid = _sessionId ?? event.sessionId;
    final turnId = event.turnId;

    switch (event) {
      case ClaudeInitEvent():
        events.add(
          CodingAgentInitEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            model: event.model,
          ),
        );

      case ClaudeAssistantEvent():
        for (final block in event.content) {
          switch (block) {
            case ClaudeTextBlock():
              events.add(
                CodingAgentTextEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  text: block.text,
                  isPartial: false,
                ),
              );
            case ClaudeThinkingBlock():
              events.add(
                CodingAgentThinkingEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  thinking: block.thinking,
                ),
              );
            case ClaudeToolUseBlock():
              events.add(
                CodingAgentToolUseEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  toolUseId: block.id,
                  toolName: block.name,
                  input: block.input,
                ),
              );
            case ClaudeToolResultBlock():
              events.add(
                CodingAgentToolResultEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  toolUseId: block.toolUseId,
                  output: block.content,
                  isError: block.isError ?? false,
                ),
              );
            case ClaudeUnknownBlock():
              events.add(
                CodingAgentUnknownEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  originalType: 'claude_block_${block.type}',
                  data: block.data,
                ),
              );
          }
        }

      case ClaudeUserEvent():
        for (final block in event.content) {
          switch (block) {
            case ClaudeToolResultBlock():
              events.add(
                CodingAgentToolResultEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  toolUseId: block.toolUseId,
                  output: block.content,
                  isError: block.isError ?? false,
                ),
              );
            case ClaudeTextBlock():
              events.add(
                CodingAgentTextEvent(
                  sessionId: sid,
                  turnId: turnId,
                  timestamp: event.timestamp,
                  text: block.text,
                  isPartial: false,
                ),
              );
            case ClaudeThinkingBlock():
            case ClaudeToolUseBlock():
            case ClaudeUnknownBlock():
              break;
          }
        }

      case ClaudeResultEvent():
        final status = switch (event.subtype) {
          'success' => CodingAgentTurnStatus.success,
          'error' => CodingAgentTurnStatus.error,
          'cancelled' => CodingAgentTurnStatus.cancelled,
          _ => CodingAgentTurnStatus.success,
        };

        CodingAgentUsage? usage;
        if (event.usage != null) {
          usage = CodingAgentUsage(
            inputTokens: event.usage!.inputTokens,
            outputTokens: event.usage!.outputTokens,
            cacheCreationInputTokens: event.usage!.cacheCreationInputTokens,
            cacheReadInputTokens: event.usage!.cacheReadInputTokens,
          );
        }

        events.add(
          CodingAgentTurnEndEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            status: status,
            usage: usage,
            durationMs: event.durationMs,
            errorMessage: event.isError ? (event.result ?? event.error) : null,
          ),
        );

      case ClaudeSystemEvent():
        events.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'claude_system_${event.subtype}',
            data: event.data,
          ),
        );

      case ClaudeToolProgressEvent():
        events.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'claude_tool_progress',
            data: {
              'tool_use_id': event.toolUseId,
              'tool_name': event.toolName,
              'elapsed_time_seconds': event.elapsedTimeSeconds,
              'parent_tool_use_id': event.parentToolUseId,
            },
          ),
        );

      case ClaudeAuthStatusEvent():
        events.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'claude_auth_status',
            data: {
              'isAuthenticating': event.isAuthenticating,
              'output': event.output,
              'error': event.error,
            },
          ),
        );

      case ClaudeUnknownEvent():
        events.add(
          CodingAgentUnknownEvent(
            sessionId: sid,
            turnId: turnId,
            timestamp: event.timestamp,
            originalType: 'claude_${event.type}',
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

class _ClaudeCodingAgentTurn implements CodingAgentTurn {
  @override
  final int turnId;

  final ClaudeSession _underlyingSession;

  _ClaudeCodingAgentTurn({
    required this.turnId,
    required ClaudeSession underlyingSession,
  }) : _underlyingSession = underlyingSession;

  @override
  Future<void> cancel() async {
    await _underlyingSession.cancel();
  }
}
