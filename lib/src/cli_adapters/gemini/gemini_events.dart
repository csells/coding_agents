import 'gemini_types.dart';

/// Base class for all Gemini events
sealed class GeminiEvent {
  /// Session ID for this event
  final String sessionId;

  /// Turn number within the session
  final int turnId;

  /// Timestamp when event occurred
  final DateTime timestamp;

  GeminiEvent({
    required this.sessionId,
    required this.turnId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory GeminiEvent.fromJson(
    Map<String, dynamic> json,
    String sessionId,
    int turnId,
  ) {
    final type = json['type'] as String?;

    switch (type) {
      case 'init':
        final sid = json['session_id'] as String? ?? sessionId;
        final model = json['model'] as String? ?? '';
        return GeminiInitEvent(
          sessionId: sid,
          turnId: turnId,
          model: model,
        );

      case 'message':
        final role = json['role'] as String? ?? 'unknown';
        final content = json['content'] as String? ?? '';
        final delta = json['delta'] as bool? ?? false;
        return GeminiMessageEvent(
          sessionId: sessionId,
          turnId: turnId,
          role: role,
          content: content,
          delta: delta,
        );

      case 'tool_use':
        final params = json['parameters'];
        final toolUse = GeminiToolUse(
          toolName: json['tool_name'] as String? ?? '',
          toolId: json['tool_id'] as String? ?? '',
          parameters: params != null
              ? Map<String, dynamic>.from(params as Map)
              : <String, dynamic>{},
        );
        return GeminiToolUseEvent(
          sessionId: sessionId,
          turnId: turnId,
          toolUse: toolUse,
        );

      case 'tool_result':
        final errorData = json['error'];
        final toolResult = GeminiToolResult(
          toolId: json['tool_id'] as String? ?? '',
          status: json['status'] as String? ?? '',
          output: json['output'] as String?,
          error: errorData != null
              ? Map<String, dynamic>.from(errorData as Map)
              : null,
        );
        return GeminiToolResultEvent(
          sessionId: sessionId,
          turnId: turnId,
          toolResult: toolResult,
        );

      case 'result':
        final status = json['status'] as String? ?? 'unknown';
        final statsData = json['stats'];
        final stats = statsData != null
            ? GeminiStats.fromJson(Map<String, dynamic>.from(statsData as Map))
            : null;
        final resultError = json['error'];
        return GeminiResultEvent(
          sessionId: sessionId,
          turnId: turnId,
          status: status,
          stats: stats,
          error: resultError != null
              ? Map<String, dynamic>.from(resultError as Map)
              : null,
        );

      case 'error':
        final errorData = json['error'];
        final errorMap = errorData != null
            ? Map<String, dynamic>.from(errorData as Map)
            : <String, dynamic>{};
        final code = errorMap['code'] as String? ?? 'UNKNOWN';
        final message = errorMap['message'] as String? ?? 'Unknown error';
        return GeminiErrorEvent(
          sessionId: sessionId,
          turnId: turnId,
          code: code,
          message: message,
        );

      case 'retry':
        return GeminiRetryEvent(
          sessionId: sessionId,
          turnId: turnId,
          attempt: json['attempt'] as int? ?? 0,
          maxAttempts: json['max_attempts'] as int? ?? 0,
          delayMs: json['delay_ms'] as int? ?? 0,
        );

      default:
        return GeminiUnknownEvent(
          sessionId: sessionId,
          turnId: turnId,
          type: type ?? 'unknown',
          data: json,
        );
    }
  }
}

/// Init event - emitted when session starts
class GeminiInitEvent extends GeminiEvent {
  final String model;

  GeminiInitEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.model,
  });
}

/// Message event - emitted for user/assistant messages
class GeminiMessageEvent extends GeminiEvent {
  final String role;
  final String content;
  final bool delta;

  GeminiMessageEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.role,
    required this.content,
    required this.delta,
  });
}

/// Tool use event - emitted when a tool is invoked
class GeminiToolUseEvent extends GeminiEvent {
  final GeminiToolUse toolUse;

  GeminiToolUseEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.toolUse,
  });
}

/// Tool result event - emitted when a tool returns a result
class GeminiToolResultEvent extends GeminiEvent {
  final GeminiToolResult toolResult;

  GeminiToolResultEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.toolResult,
  });
}

/// Result event - emitted when turn or session completes
class GeminiResultEvent extends GeminiEvent {
  final String status;
  final GeminiStats? stats;
  final Map<String, dynamic>? error;

  GeminiResultEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.status,
    this.stats,
    this.error,
  });
}

/// Error event - emitted when an error occurs
class GeminiErrorEvent extends GeminiEvent {
  final String code;
  final String message;

  GeminiErrorEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.code,
    required this.message,
  });
}

/// Retry event - emitted when retrying an operation
class GeminiRetryEvent extends GeminiEvent {
  final int attempt;
  final int maxAttempts;
  final int delayMs;

  GeminiRetryEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.attempt,
    required this.maxAttempts,
    required this.delayMs,
  });
}

/// Unknown event type for forward compatibility
class GeminiUnknownEvent extends GeminiEvent {
  final String type;
  final Map<String, dynamic> data;

  GeminiUnknownEvent({
    required super.sessionId,
    required super.turnId,
    super.timestamp,
    required this.type,
    required this.data,
  });
}
