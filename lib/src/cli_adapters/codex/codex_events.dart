import 'codex_types.dart';

/// Base class for all Codex events
sealed class CodexEvent {
  /// Thread ID for this event
  final String threadId;

  /// Turn number within the session
  final int turnId;

  /// Timestamp when event was received
  final DateTime timestamp;

  CodexEvent({
    required this.threadId,
    required this.turnId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory CodexEvent.fromJson(
    Map<String, dynamic> json,
    String threadId,
    int turnId,
  ) {
    final type = json['type'] as String?;

    switch (type) {
      case 'thread.started':
        final tid = json['thread_id'] as String? ?? threadId;
        return CodexThreadStartedEvent(threadId: tid, turnId: turnId);

      case 'turn.started':
        return CodexTurnStartedEvent(threadId: threadId, turnId: turnId);

      case 'turn.completed':
        final usageJson = json['usage'] as Map<String, dynamic>?;
        final usage = usageJson != null ? CodexUsage.fromJson(usageJson) : null;
        return CodexTurnCompletedEvent(
          threadId: threadId,
          turnId: turnId,
          usage: usage,
        );

      case 'turn.failed':
        final error = json['error'] as Map<String, dynamic>?;
        final message = error?['message'] as String? ?? 'Unknown error';
        return CodexTurnFailedEvent(
          threadId: threadId,
          turnId: turnId,
          message: message,
        );

      case 'item.started':
        final itemJson = json['item'] as Map<String, dynamic>;
        final item = CodexItem.fromJson(itemJson);
        return CodexItemStartedEvent(
          threadId: threadId,
          turnId: turnId,
          item: item,
        );

      case 'item.updated':
        final itemJson = json['item'] as Map<String, dynamic>;
        final item = CodexItem.fromJson(itemJson);
        return CodexItemUpdatedEvent(
          threadId: threadId,
          turnId: turnId,
          item: item,
        );

      case 'item.completed':
        final itemJson = json['item'] as Map<String, dynamic>;
        final item = CodexItem.fromJson(itemJson);
        final status = json['status'] as String? ?? 'unknown';
        return CodexItemCompletedEvent(
          threadId: threadId,
          turnId: turnId,
          item: item,
          status: status,
        );

      case 'error':
        final message = json['message'] as String? ?? 'Unknown error';
        return CodexErrorEvent(
          threadId: threadId,
          turnId: turnId,
          message: message,
        );

      case 'session_meta':
        final payload = json['payload'] as Map<String, dynamic>?;
        return CodexSessionMetaEvent(
          threadId: payload?['id'] as String? ?? threadId,
          turnId: turnId,
          cwd: payload?['cwd'] as String?,
          model: payload?['model_provider'] as String?,
        );

      case 'event_msg':
        final payload = json['payload'] as Map<String, dynamic>?;
        final msgType = payload?['type'] as String?;
        if (msgType == 'user_message') {
          return CodexUserMessageEvent(
            threadId: threadId,
            turnId: turnId,
            message: payload?['message'] as String? ?? '',
          );
        }
        if (msgType == 'agent_message') {
          return CodexAgentMessageEvent(
            threadId: threadId,
            turnId: turnId,
            message: payload?['message'] as String? ?? '',
          );
        }
        return CodexUnknownEvent(
          threadId: threadId,
          turnId: turnId,
          type: 'event_msg:$msgType',
          data: json,
        );

      default:
        return CodexUnknownEvent(
          threadId: threadId,
          turnId: turnId,
          type: type ?? 'unknown',
          data: json,
        );
    }
  }
}

/// Thread started event - emitted when a new thread is created
class CodexThreadStartedEvent extends CodexEvent {
  CodexThreadStartedEvent({
    required super.threadId,
    required super.turnId,
    super.timestamp,
  });
}

/// Turn started event - emitted when a new turn begins
class CodexTurnStartedEvent extends CodexEvent {
  CodexTurnStartedEvent({
    required super.threadId,
    required super.turnId,
    super.timestamp,
  });
}

/// Turn completed event - emitted when a turn completes successfully
class CodexTurnCompletedEvent extends CodexEvent {
  final CodexUsage? usage;

  CodexTurnCompletedEvent({
    required super.threadId,
    required super.turnId,
    super.timestamp,
    this.usage,
  });
}

/// Turn failed event - emitted when a turn fails
class CodexTurnFailedEvent extends CodexEvent {
  final String message;

  CodexTurnFailedEvent({
    required super.threadId,
    required super.turnId,
    super.timestamp,
    required this.message,
  });
}

/// Item started event - emitted when an item begins streaming
class CodexItemStartedEvent extends CodexEvent {
  final CodexItem item;

  CodexItemStartedEvent({
    required super.threadId,
    required super.turnId,
    super.timestamp,
    required this.item,
  });
}

/// Item updated event - emitted when an item is updated during streaming
class CodexItemUpdatedEvent extends CodexEvent {
  final CodexItem item;

  CodexItemUpdatedEvent({
    required super.threadId,
    required super.turnId,
    super.timestamp,
    required this.item,
  });
}

/// Item completed event - emitted when an item finishes streaming
class CodexItemCompletedEvent extends CodexEvent {
  final CodexItem item;
  final String status;

  CodexItemCompletedEvent({
    required super.threadId,
    required super.turnId,
    super.timestamp,
    required this.item,
    required this.status,
  });
}

/// Error event - emitted when an error occurs
class CodexErrorEvent extends CodexEvent {
  final String message;

  CodexErrorEvent({
    required super.threadId,
    required super.turnId,
    super.timestamp,
    required this.message,
  });
}

/// Session metadata event - contains session info including cwd
class CodexSessionMetaEvent extends CodexEvent {
  final String? cwd;
  final String? model;

  CodexSessionMetaEvent({
    required super.threadId,
    required super.turnId,
    super.timestamp,
    this.cwd,
    this.model,
  });
}

/// User message event - contains the user's prompt
class CodexUserMessageEvent extends CodexEvent {
  final String message;

  CodexUserMessageEvent({
    required super.threadId,
    required super.turnId,
    super.timestamp,
    required this.message,
  });
}

/// Agent message event - contains the agent's response
class CodexAgentMessageEvent extends CodexEvent {
  final String message;

  CodexAgentMessageEvent({
    required super.threadId,
    required super.turnId,
    super.timestamp,
    required this.message,
  });
}

/// Unknown event type for forward compatibility
class CodexUnknownEvent extends CodexEvent {
  final String type;
  final Map<String, dynamic> data;

  CodexUnknownEvent({
    required super.threadId,
    required super.turnId,
    super.timestamp,
    required this.type,
    required this.data,
  });
}
