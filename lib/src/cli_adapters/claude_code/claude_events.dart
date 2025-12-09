import 'claude_types.dart';

/// Base class for all Claude streaming events
sealed class ClaudeEvent {
  final String sessionId;
  final int turnId;
  final DateTime timestamp;

  const ClaudeEvent({
    required this.sessionId,
    required this.turnId,
    required this.timestamp,
  });

  factory ClaudeEvent.fromJson(Map<String, dynamic> json, int turnId) {
    final type = json['type'] as String;
    final sessionId = json['session_id'] as String? ?? '';
    final timestamp =
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now();

    return switch (type) {
      'init' => ClaudeInitEvent.fromJson(json, turnId),
      'assistant' => ClaudeAssistantEvent.fromJson(json, turnId),
      'user' => ClaudeUserEvent.fromJson(json, turnId),
      'result' => ClaudeResultEvent.fromJson(json, turnId),
      'system' => ClaudeSystemEvent.fromJson(json, turnId),
      'tool_progress' => ClaudeToolProgressEvent.fromJson(json, turnId),
      'auth_status' => ClaudeAuthStatusEvent.fromJson(json, turnId),
      _ => ClaudeUnknownEvent(
        sessionId: sessionId,
        turnId: turnId,
        timestamp: timestamp,
        type: type,
        data: json,
      ),
    };
  }
}

/// Session initialization event
class ClaudeInitEvent extends ClaudeEvent {
  final String model;

  ClaudeInitEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.model,
  });

  factory ClaudeInitEvent.fromJson(Map<String, dynamic> json, int turnId) =>
      ClaudeInitEvent(
        sessionId: json['session_id'] as String,
        turnId: turnId,
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        model: json['model'] as String? ?? '',
      );
}

/// Assistant message event
class ClaudeAssistantEvent extends ClaudeEvent {
  final List<ClaudeContentBlock> content;
  final ClaudeUsage? usage;

  ClaudeAssistantEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.content,
    this.usage,
  });

  factory ClaudeAssistantEvent.fromJson(Map<String, dynamic> json, int turnId) {
    // Note: session_id may be absent in history files; context knows the session
    final sessionId = json['session_id'] as String? ?? '';

    final message = json['message'] as Map<String, dynamic>?;
    final contentList =
        (message?['content'] as List<dynamic>?)
            ?.map((e) => ClaudeContentBlock.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final usage = message?['usage'] != null
        ? ClaudeUsage.fromJson(message!['usage'] as Map<String, dynamic>)
        : null;

    return ClaudeAssistantEvent(
      sessionId: sessionId,
      turnId: turnId,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      content: contentList,
      usage: usage,
    );
  }
}

/// User message event (typically tool results)
class ClaudeUserEvent extends ClaudeEvent {
  final List<ClaudeContentBlock> content;

  ClaudeUserEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.content,
  });

  factory ClaudeUserEvent.fromJson(Map<String, dynamic> json, int turnId) {
    // Note: session_id may be absent in user events from session history files
    // since user events (tool results) are internal to the session context
    final sessionId = json['session_id'] as String? ?? '';

    final message = json['message'] as Map<String, dynamic>?;
    final rawContent = message?['content'];

    // Content can be a List of blocks or a simple String
    List<ClaudeContentBlock> contentList;
    if (rawContent is List) {
      contentList = rawContent
          .map((e) => ClaudeContentBlock.fromJson(e as Map<String, dynamic>))
          .toList();
    } else if (rawContent is String) {
      contentList = [ClaudeTextBlock(text: rawContent)];
    } else {
      contentList = [];
    }

    return ClaudeUserEvent(
      sessionId: sessionId,
      turnId: turnId,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      content: contentList,
    );
  }
}

/// Turn/session result event
class ClaudeResultEvent extends ClaudeEvent {
  final String subtype; // "success", "error", "cancelled"
  final bool isError; // true if the result contains an error
  final String? result; // result text (contains error message when isError)
  final double? costUsd;
  final int? durationMs;
  final ClaudeUsage? usage;
  final String? error;

  ClaudeResultEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.subtype,
    this.isError = false,
    this.result,
    this.costUsd,
    this.durationMs,
    this.usage,
    this.error,
  });

  factory ClaudeResultEvent.fromJson(Map<String, dynamic> json, int turnId) {
    // Note: session_id may be absent in history files; context knows the session
    final sessionId = json['session_id'] as String? ?? '';

    return ClaudeResultEvent(
      sessionId: sessionId,
      turnId: turnId,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      subtype: json['subtype'] as String? ?? 'unknown',
      isError: json['is_error'] as bool? ?? false,
      result: json['result'] as String?,
      costUsd: (json['cost_usd'] as num?)?.toDouble(),
      durationMs: json['duration_ms'] as int?,
      usage: json['usage'] != null
          ? ClaudeUsage.fromJson(json['usage'] as Map<String, dynamic>)
          : null,
      error: json['error'] as String?,
    );
  }
}

/// System event (init info, compaction, etc.)
class ClaudeSystemEvent extends ClaudeEvent {
  final String subtype;
  final Map<String, dynamic> data;

  ClaudeSystemEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.subtype,
    required this.data,
  });

  factory ClaudeSystemEvent.fromJson(Map<String, dynamic> json, int turnId) {
    // Note: session_id may be absent in history files; context knows the session
    final sessionId = json['session_id'] as String? ?? '';

    return ClaudeSystemEvent(
      sessionId: sessionId,
      turnId: turnId,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      subtype: json['subtype'] as String? ?? 'unknown',
      data: json,
    );
  }
}

/// Tool progress event - real-time updates during tool execution
class ClaudeToolProgressEvent extends ClaudeEvent {
  final String toolUseId;
  final String toolName;
  final double elapsedTimeSeconds;
  final String? parentToolUseId;

  ClaudeToolProgressEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.toolUseId,
    required this.toolName,
    required this.elapsedTimeSeconds,
    this.parentToolUseId,
  });

  factory ClaudeToolProgressEvent.fromJson(
    Map<String, dynamic> json,
    int turnId,
  ) {
    // Note: session_id may be absent in history files
    final sessionId = json['session_id'] as String? ?? '';
    final toolUseId = json['tool_use_id'] as String?;
    if (toolUseId == null) {
      throw FormatException(
        'Missing required field "tool_use_id" in tool_progress event',
      );
    }
    final toolName = json['tool_name'] as String?;
    if (toolName == null) {
      throw FormatException(
        'Missing required field "tool_name" in tool_progress event',
      );
    }

    return ClaudeToolProgressEvent(
      sessionId: sessionId,
      turnId: turnId,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      toolUseId: toolUseId,
      toolName: toolName,
      elapsedTimeSeconds:
          (json['elapsed_time_seconds'] as num?)?.toDouble() ?? 0.0,
      parentToolUseId: json['parent_tool_use_id'] as String?,
    );
  }
}

/// Authentication status event
class ClaudeAuthStatusEvent extends ClaudeEvent {
  final bool isAuthenticating;
  final List<String> output;
  final String? error;

  ClaudeAuthStatusEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.isAuthenticating,
    required this.output,
    this.error,
  });

  factory ClaudeAuthStatusEvent.fromJson(
    Map<String, dynamic> json,
    int turnId,
  ) {
    // Note: session_id may be absent in history files
    final sessionId = json['session_id'] as String? ?? '';

    return ClaudeAuthStatusEvent(
      sessionId: sessionId,
      turnId: turnId,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      isAuthenticating: json['isAuthenticating'] as bool? ?? false,
      output: (json['output'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      error: json['error'] as String?,
    );
  }
}

/// Unknown event type (forward compatibility)
class ClaudeUnknownEvent extends ClaudeEvent {
  final String type;
  final Map<String, dynamic> data;

  ClaudeUnknownEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.type,
    required this.data,
  });
}
