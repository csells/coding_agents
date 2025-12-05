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
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
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
    final message = json['message'] as Map<String, dynamic>?;
    final contentList = (message?['content'] as List<dynamic>?)
            ?.map((e) => ClaudeContentBlock.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    final usage = message?['usage'] != null
        ? ClaudeUsage.fromJson(message!['usage'] as Map<String, dynamic>)
        : null;

    return ClaudeAssistantEvent(
      sessionId: json['session_id'] as String? ?? '',
      turnId: turnId,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
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
      sessionId: json['session_id'] as String? ?? '',
      turnId: turnId,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
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

  factory ClaudeResultEvent.fromJson(Map<String, dynamic> json, int turnId) =>
      ClaudeResultEvent(
        sessionId: json['session_id'] as String? ?? '',
        turnId: turnId,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
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

  factory ClaudeSystemEvent.fromJson(Map<String, dynamic> json, int turnId) =>
      ClaudeSystemEvent(
        sessionId: json['session_id'] as String? ?? '',
        turnId: turnId,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        subtype: json['subtype'] as String? ?? 'unknown',
        data: json,
      );
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
