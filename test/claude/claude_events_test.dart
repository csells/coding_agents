import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/claude/claude_events.dart';
import 'package:coding_agents/src/cli_adapters/claude/claude_types.dart';

void main() {
  group('ClaudeEvent.fromJson', () {
    test('parses init event', () {
      final json = {
        'type': 'init',
        'session_id': 'sess_abc123',
        'timestamp': '2025-01-01T10:00:00.000Z',
        'model': 'claude-sonnet-4-5-20250929',
      };

      final event = ClaudeEvent.fromJson(json, 1);

      expect(event, isA<ClaudeInitEvent>());
      final initEvent = event as ClaudeInitEvent;
      expect(initEvent.sessionId, 'sess_abc123');
      expect(initEvent.model, 'claude-sonnet-4-5-20250929');
      expect(initEvent.turnId, 1);
    });

    test('parses assistant message event', () {
      final json = {
        'type': 'assistant',
        'session_id': 'sess_abc123',
        'timestamp': '2025-01-01T10:00:01.000Z',
        'message': {
          'content': [
            {'type': 'text', 'text': 'Hello, I can help you with that.'},
          ],
          'usage': {
            'inputTokens': 100,
            'outputTokens': 50,
          },
        },
      };

      final event = ClaudeEvent.fromJson(json, 1);

      expect(event, isA<ClaudeAssistantEvent>());
      final assistantEvent = event as ClaudeAssistantEvent;
      expect(assistantEvent.content, hasLength(1));
      expect(assistantEvent.content.first, isA<ClaudeTextBlock>());
      expect((assistantEvent.content.first as ClaudeTextBlock).text,
          'Hello, I can help you with that.');
      expect(assistantEvent.usage?.inputTokens, 100);
      expect(assistantEvent.usage?.outputTokens, 50);
    });

    test('parses assistant message with tool use', () {
      final json = {
        'type': 'assistant',
        'session_id': 'sess_abc123',
        'message': {
          'content': [
            {'type': 'text', 'text': 'Let me read that file.'},
            {
              'type': 'tool_use',
              'id': 'toolu_01ABC',
              'name': 'Read',
              'input': {'file_path': '/src/main.dart'},
            },
          ],
        },
      };

      final event = ClaudeEvent.fromJson(json, 2);

      expect(event, isA<ClaudeAssistantEvent>());
      final assistantEvent = event as ClaudeAssistantEvent;
      expect(assistantEvent.content, hasLength(2));
      expect(assistantEvent.content[0], isA<ClaudeTextBlock>());
      expect(assistantEvent.content[1], isA<ClaudeToolUseBlock>());

      final toolUse = assistantEvent.content[1] as ClaudeToolUseBlock;
      expect(toolUse.id, 'toolu_01ABC');
      expect(toolUse.name, 'Read');
      expect(toolUse.input['file_path'], '/src/main.dart');
    });

    test('parses user message event with tool result', () {
      final json = {
        'type': 'user',
        'session_id': 'sess_abc123',
        'message': {
          'content': [
            {
              'type': 'tool_result',
              'toolUseId': 'toolu_01ABC',
              'content': 'void main() { print("Hello"); }',
              'isError': false,
            },
          ],
        },
      };

      final event = ClaudeEvent.fromJson(json, 2);

      expect(event, isA<ClaudeUserEvent>());
      final userEvent = event as ClaudeUserEvent;
      expect(userEvent.content, hasLength(1));
      expect(userEvent.content.first, isA<ClaudeToolResultBlock>());

      final toolResult = userEvent.content.first as ClaudeToolResultBlock;
      expect(toolResult.toolUseId, 'toolu_01ABC');
      expect(toolResult.content, 'void main() { print("Hello"); }');
      expect(toolResult.isError, false);
    });

    test('parses result event with success', () {
      final json = {
        'type': 'result',
        'session_id': 'sess_abc123',
        'subtype': 'success',
        'cost_usd': 0.0025,
        'duration_ms': 5000,
        'usage': {
          'inputTokens': 1000,
          'outputTokens': 500,
        },
      };

      final event = ClaudeEvent.fromJson(json, 3);

      expect(event, isA<ClaudeResultEvent>());
      final resultEvent = event as ClaudeResultEvent;
      expect(resultEvent.subtype, 'success');
      expect(resultEvent.costUsd, 0.0025);
      expect(resultEvent.durationMs, 5000);
      expect(resultEvent.usage?.inputTokens, 1000);
      expect(resultEvent.usage?.outputTokens, 500);
      expect(resultEvent.error, isNull);
    });

    test('parses result event with error', () {
      final json = {
        'type': 'result',
        'session_id': 'sess_abc123',
        'subtype': 'error',
        'error': 'Rate limit exceeded',
      };

      final event = ClaudeEvent.fromJson(json, 3);

      expect(event, isA<ClaudeResultEvent>());
      final resultEvent = event as ClaudeResultEvent;
      expect(resultEvent.subtype, 'error');
      expect(resultEvent.error, 'Rate limit exceeded');
    });

    test('parses system event with init subtype', () {
      final json = {
        'type': 'system',
        'session_id': 'sess_abc123',
        'subtype': 'init',
        'version': '1.0.32',
        'cwd': '/path/to/project',
        'tools': ['Read', 'Edit', 'Write', 'Bash'],
      };

      final event = ClaudeEvent.fromJson(json, 1);

      expect(event, isA<ClaudeSystemEvent>());
      final systemEvent = event as ClaudeSystemEvent;
      expect(systemEvent.subtype, 'init');
      expect(systemEvent.data['version'], '1.0.32');
      expect(systemEvent.data['tools'], hasLength(4));
    });

    test('parses system event with compact_boundary subtype', () {
      final json = {
        'type': 'system',
        'session_id': 'sess_abc123',
        'subtype': 'compact_boundary',
        'compact_metadata': {
          'trigger': 'auto',
          'pre_tokens': 50000,
          'post_tokens': 25000,
        },
      };

      final event = ClaudeEvent.fromJson(json, 5);

      expect(event, isA<ClaudeSystemEvent>());
      final systemEvent = event as ClaudeSystemEvent;
      expect(systemEvent.subtype, 'compact_boundary');
    });

    test('parses unknown event type gracefully', () {
      final json = {
        'type': 'future_event_type',
        'session_id': 'sess_abc123',
        'some_field': 'some_value',
      };

      final event = ClaudeEvent.fromJson(json, 1);

      expect(event, isA<ClaudeUnknownEvent>());
      final unknownEvent = event as ClaudeUnknownEvent;
      expect(unknownEvent.type, 'future_event_type');
      expect(unknownEvent.data['some_field'], 'some_value');
    });

    test('handles missing optional fields', () {
      final json = {
        'type': 'init',
        'session_id': 'sess_abc123',
      };

      final event = ClaudeEvent.fromJson(json, 1);

      expect(event, isA<ClaudeInitEvent>());
      final initEvent = event as ClaudeInitEvent;
      expect(initEvent.sessionId, 'sess_abc123');
      expect(initEvent.model, ''); // Default empty string
    });

    test('preserves turnId across all event types', () {
      final events = [
        {'type': 'init', 'session_id': 's1'},
        {'type': 'assistant', 'session_id': 's1', 'message': {'content': []}},
        {'type': 'user', 'session_id': 's1', 'message': {'content': []}},
        {'type': 'result', 'session_id': 's1', 'subtype': 'success'},
        {'type': 'system', 'session_id': 's1', 'subtype': 'init'},
      ];

      for (var i = 0; i < events.length; i++) {
        final event = ClaudeEvent.fromJson(events[i], 42);
        expect(event.turnId, 42, reason: 'Event type ${events[i]['type']} should preserve turnId');
      }
    });
  });

  group('ClaudeEvent properties', () {
    test('all events have sessionId, turnId, and timestamp', () {
      final json = {
        'type': 'init',
        'session_id': 'sess_test',
        'timestamp': '2025-01-01T12:00:00.000Z',
      };

      final event = ClaudeEvent.fromJson(json, 7);

      expect(event.sessionId, 'sess_test');
      expect(event.turnId, 7);
      expect(event.timestamp, isA<DateTime>());
    });
  });
}
