import 'coding_agent_types.dart';

/// Base class for all coding agent events
sealed class CodingAgentEvent {
  /// Session ID this event belongs to
  final String sessionId;

  /// Turn ID within the session
  final int turnId;

  /// When the event occurred
  final DateTime timestamp;

  CodingAgentEvent({
    required this.sessionId,
    required this.turnId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Session initialization event
class CodingAgentInitEvent extends CodingAgentEvent {
  /// Model being used (if available)
  final String? model;

  CodingAgentInitEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    this.model,
  });
}

/// Text output from the agent
class CodingAgentTextEvent extends CodingAgentEvent {
  /// The text content
  final String text;

  /// Whether this is a partial/streaming update
  final bool isPartial;

  CodingAgentTextEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.text,
    this.isPartial = false,
  });
}

/// Reasoning/thinking output from the agent
class CodingAgentThinkingEvent extends CodingAgentEvent {
  /// The thinking/reasoning content
  final String thinking;

  /// Optional summary of the thinking
  final String? summary;

  CodingAgentThinkingEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.thinking,
    this.summary,
  });
}

/// Tool invocation request
class CodingAgentToolUseEvent extends CodingAgentEvent {
  /// Unique identifier for this tool use
  final String toolUseId;

  /// Name of the tool being invoked
  final String toolName;

  /// Input parameters for the tool
  final Map<String, dynamic> input;

  CodingAgentToolUseEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.toolUseId,
    required this.toolName,
    required this.input,
  });
}

/// Tool execution result
class CodingAgentToolResultEvent extends CodingAgentEvent {
  /// ID of the tool use this result corresponds to
  final String toolUseId;

  /// Output from the tool
  final String? output;

  /// Whether the tool execution resulted in an error
  final bool isError;

  /// Error message if isError is true
  final String? errorMessage;

  CodingAgentToolResultEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.toolUseId,
    this.output,
    this.isError = false,
    this.errorMessage,
  });
}

/// Turn completed event with usage statistics
class CodingAgentTurnEndEvent extends CodingAgentEvent {
  /// Whether the turn completed successfully
  final CodingAgentTurnStatus status;

  /// Token usage for this turn
  final CodingAgentUsage? usage;

  /// Duration of the turn in milliseconds
  final int? durationMs;

  /// Error message if status is error
  final String? errorMessage;

  CodingAgentTurnEndEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.status,
    this.usage,
    this.durationMs,
    this.errorMessage,
  });
}

/// Error event (can occur at any time)
class CodingAgentErrorEvent extends CodingAgentEvent {
  /// Error code (adapter-specific)
  final String? code;

  /// Human-readable error message
  final String message;

  CodingAgentErrorEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    this.code,
    required this.message,
  });
}

/// Unknown event type for forward compatibility
class CodingAgentUnknownEvent extends CodingAgentEvent {
  /// Original event type string
  final String originalType;

  /// Raw event data
  final Map<String, dynamic> data;

  CodingAgentUnknownEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.originalType,
    required this.data,
  });
}
