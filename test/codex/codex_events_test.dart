import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_events.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_types.dart';

void main() {
  group('CodexEvent.fromJson', () {
    test('parses thread.started event', () {
      final json = {'type': 'thread.started', 'thread_id': 'thread_abc123'};

      final event = CodexEvent.fromJson(json, '', 1);

      expect(event, isA<CodexThreadStartedEvent>());
      final threadStarted = event as CodexThreadStartedEvent;
      expect(threadStarted.threadId, 'thread_abc123');
      expect(threadStarted.turnId, 1);
    });

    test('parses turn.started event', () {
      final json = {'type': 'turn.started'};

      final event = CodexEvent.fromJson(json, 'thread_123', 2);

      expect(event, isA<CodexTurnStartedEvent>());
      expect(event.threadId, 'thread_123');
      expect(event.turnId, 2);
    });

    test('parses turn.completed event with usage', () {
      final json = {
        'type': 'turn.completed',
        'usage': {
          'inputTokens': 1000,
          'outputTokens': 500,
          'cachedInputTokens': 200,
        },
      };

      final event = CodexEvent.fromJson(json, 'thread_123', 2);

      expect(event, isA<CodexTurnCompletedEvent>());
      final turnCompleted = event as CodexTurnCompletedEvent;
      expect(turnCompleted.usage, isNotNull);
      expect(turnCompleted.usage!.inputTokens, 1000);
      expect(turnCompleted.usage!.outputTokens, 500);
      expect(turnCompleted.usage!.cachedInputTokens, 200);
    });

    test('parses turn.completed event without usage', () {
      final json = {'type': 'turn.completed'};

      final event = CodexEvent.fromJson(json, 'thread_123', 2);

      expect(event, isA<CodexTurnCompletedEvent>());
      final turnCompleted = event as CodexTurnCompletedEvent;
      expect(turnCompleted.usage, isNull);
    });

    test('parses turn.failed event', () {
      final json = {
        'type': 'turn.failed',
        'error': {'message': 'Tool execution failed: permission denied'},
      };

      final event = CodexEvent.fromJson(json, 'thread_123', 3);

      expect(event, isA<CodexTurnFailedEvent>());
      final turnFailed = event as CodexTurnFailedEvent;
      expect(turnFailed.message, 'Tool execution failed: permission denied');
    });

    test('parses item.started event', () {
      final json = {
        'type': 'item.started',
        'item': {'type': 'agent_message', 'id': 'msg_01', 'text': ''},
      };

      final event = CodexEvent.fromJson(json, 'thread_123', 2);

      expect(event, isA<CodexItemStartedEvent>());
      final itemStarted = event as CodexItemStartedEvent;
      expect(itemStarted.item, isA<CodexAgentMessageItem>());
    });

    test('parses item.updated event with agent_message', () {
      final json = {
        'type': 'item.updated',
        'item': {
          'type': 'agent_message',
          'id': 'msg_01',
          'text': 'I will analyze the code...',
        },
      };

      final event = CodexEvent.fromJson(json, 'thread_123', 2);

      expect(event, isA<CodexItemUpdatedEvent>());
      final itemUpdated = event as CodexItemUpdatedEvent;
      expect(itemUpdated.item, isA<CodexAgentMessageItem>());
      expect(
        (itemUpdated.item as CodexAgentMessageItem).text,
        'I will analyze the code...',
      );
    });

    test('parses item.updated event with command_execution', () {
      final json = {
        'type': 'item.updated',
        'item': {
          'type': 'tool_call',
          'id': 'cmd_01',
          'name': 'shell',
          'arguments': {'command': 'npm test'},
          'output': 'Tests passing...',
        },
      };

      final event = CodexEvent.fromJson(json, 'thread_123', 2);

      expect(event, isA<CodexItemUpdatedEvent>());
      final itemUpdated = event as CodexItemUpdatedEvent;
      expect(itemUpdated.item, isA<CodexToolCallItem>());
    });

    test('parses item.updated event with file_change', () {
      final json = {
        'type': 'item.updated',
        'item': {
          'type': 'file_change',
          'id': 'file_01',
          'path': 'src/main.dart',
          'before': 'old',
          'after': 'new',
        },
      };

      final event = CodexEvent.fromJson(json, 'thread_123', 2);

      expect(event, isA<CodexItemUpdatedEvent>());
      final itemUpdated = event as CodexItemUpdatedEvent;
      expect(itemUpdated.item, isA<CodexFileChangeItem>());
    });

    test('parses item.updated event with reasoning', () {
      final json = {
        'type': 'item.updated',
        'item': {
          'type': 'reasoning',
          'id': 'reason_01',
          'reasoning': 'First, I need to understand the structure...',
          'summary': 'Analyzing code structure',
        },
      };

      final event = CodexEvent.fromJson(json, 'thread_123', 2);

      expect(event, isA<CodexItemUpdatedEvent>());
      final itemUpdated = event as CodexItemUpdatedEvent;
      expect(itemUpdated.item, isA<CodexReasoningItem>());
    });

    test('parses item.completed event with success status', () {
      final json = {
        'type': 'item.completed',
        'item': {'type': 'agent_message', 'id': 'msg_01', 'text': 'Done!'},
        'status': 'success',
      };

      final event = CodexEvent.fromJson(json, 'thread_123', 2);

      expect(event, isA<CodexItemCompletedEvent>());
      final itemCompleted = event as CodexItemCompletedEvent;
      expect(itemCompleted.status, 'success');
      expect(itemCompleted.item, isA<CodexAgentMessageItem>());
    });

    test('parses item.completed event with failed status', () {
      final json = {
        'type': 'item.completed',
        'item': {
          'type': 'tool_call',
          'id': 'cmd_01',
          'name': 'shell',
          'arguments': {'command': 'npm test'},
          'exit_code': 1,
        },
        'status': 'failed',
      };

      final event = CodexEvent.fromJson(json, 'thread_123', 2);

      expect(event, isA<CodexItemCompletedEvent>());
      final itemCompleted = event as CodexItemCompletedEvent;
      expect(itemCompleted.status, 'failed');
    });

    test('parses error event', () {
      final json = {
        'type': 'error',
        'message': 'Session terminated unexpectedly',
      };

      final event = CodexEvent.fromJson(json, 'thread_123', 2);

      expect(event, isA<CodexErrorEvent>());
      final errorEvent = event as CodexErrorEvent;
      expect(errorEvent.message, 'Session terminated unexpectedly');
    });

    test('parses unknown event type gracefully', () {
      final json = {'type': 'future_event_type', 'some_field': 'some_value'};

      final event = CodexEvent.fromJson(json, 'thread_123', 1);

      expect(event, isA<CodexUnknownEvent>());
      final unknownEvent = event as CodexUnknownEvent;
      expect(unknownEvent.type, 'future_event_type');
    });

    test('preserves threadId and turnId across all event types', () {
      final events = [
        {'type': 'thread.started', 'thread_id': 't1'},
        {'type': 'turn.started'},
        {'type': 'turn.completed'},
        {
          'type': 'turn.failed',
          'error': {'message': 'err'},
        },
        {
          'type': 'item.started',
          'item': {'type': 'agent_message', 'id': '1', 'text': ''},
        },
        {
          'type': 'item.updated',
          'item': {'type': 'agent_message', 'id': '1', 'text': ''},
        },
        {
          'type': 'item.completed',
          'item': {'type': 'agent_message', 'id': '1', 'text': ''},
          'status': 'success',
        },
        {'type': 'error', 'message': 'test'},
      ];

      for (final eventJson in events) {
        final event = CodexEvent.fromJson(eventJson, 'thread_test', 42);
        expect(
          event.turnId,
          42,
          reason: 'Event type ${eventJson['type']} should preserve turnId',
        );
      }
    });
  });

  group('CodexEvent properties', () {
    test('all events have threadId, turnId, and timestamp', () {
      final json = {'type': 'turn.started'};

      final event = CodexEvent.fromJson(json, 'thread_test', 7);

      expect(event.threadId, 'thread_test');
      expect(event.turnId, 7);
      expect(event.timestamp, isA<DateTime>());
    });
  });
}
