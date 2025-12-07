import 'package:coding_agents/src/coding_agent/coding_agent_events.dart';
import 'package:coding_agents/src/coding_agent/coding_agent_types.dart';
import 'package:test/test.dart';

void main() {
  group('CodingAgentInitEvent', () {
    test('stores all fields correctly', () {
      final timestamp = DateTime.now();
      final event = CodingAgentInitEvent(
        sessionId: 'sess_123',
        turnId: 0,
        timestamp: timestamp,
        model: 'claude-opus-4',
      );

      expect(event.sessionId, equals('sess_123'));
      expect(event.turnId, equals(0));
      expect(event.timestamp, equals(timestamp));
      expect(event.model, equals('claude-opus-4'));
    });

    test('model is optional', () {
      final event = CodingAgentInitEvent(
        sessionId: 'sess_123',
        turnId: 0,
      );

      expect(event.model, isNull);
    });

    test('uses current time if timestamp not provided', () {
      final before = DateTime.now();
      final event = CodingAgentInitEvent(
        sessionId: 'sess_123',
        turnId: 0,
      );
      final after = DateTime.now();

      expect(event.timestamp.isAfter(before) || event.timestamp.isAtSameMomentAs(before), isTrue);
      expect(event.timestamp.isBefore(after) || event.timestamp.isAtSameMomentAs(after), isTrue);
    });
  });

  group('CodingAgentTextEvent', () {
    test('stores text correctly', () {
      final event = CodingAgentTextEvent(
        sessionId: 'sess_123',
        turnId: 0,
        text: 'Hello, world!',
      );

      expect(event.text, equals('Hello, world!'));
      expect(event.isPartial, isFalse);
    });

    test('isPartial defaults to false', () {
      final event = CodingAgentTextEvent(
        sessionId: 'sess_123',
        turnId: 0,
        text: 'Hello',
      );

      expect(event.isPartial, isFalse);
    });

    test('can be marked as partial', () {
      final event = CodingAgentTextEvent(
        sessionId: 'sess_123',
        turnId: 0,
        text: 'Hel',
        isPartial: true,
      );

      expect(event.isPartial, isTrue);
    });
  });

  group('CodingAgentThinkingEvent', () {
    test('stores thinking content', () {
      final event = CodingAgentThinkingEvent(
        sessionId: 'sess_123',
        turnId: 0,
        thinking: 'Let me think about this...',
      );

      expect(event.thinking, equals('Let me think about this...'));
      expect(event.summary, isNull);
    });

    test('can include summary', () {
      final event = CodingAgentThinkingEvent(
        sessionId: 'sess_123',
        turnId: 0,
        thinking: 'Long thinking process...',
        summary: 'Analyzed the problem',
      );

      expect(event.summary, equals('Analyzed the problem'));
    });
  });

  group('CodingAgentToolUseEvent', () {
    test('stores tool use details', () {
      final event = CodingAgentToolUseEvent(
        sessionId: 'sess_123',
        turnId: 0,
        toolUseId: 'tool_abc',
        toolName: 'Read',
        input: {'file_path': '/path/to/file.dart'},
      );

      expect(event.toolUseId, equals('tool_abc'));
      expect(event.toolName, equals('Read'));
      expect(event.input, equals({'file_path': '/path/to/file.dart'}));
    });
  });

  group('CodingAgentToolResultEvent', () {
    test('stores successful result', () {
      final event = CodingAgentToolResultEvent(
        sessionId: 'sess_123',
        turnId: 0,
        toolUseId: 'tool_abc',
        output: 'File contents here...',
      );

      expect(event.toolUseId, equals('tool_abc'));
      expect(event.output, equals('File contents here...'));
      expect(event.isError, isFalse);
      expect(event.errorMessage, isNull);
    });

    test('stores error result', () {
      final event = CodingAgentToolResultEvent(
        sessionId: 'sess_123',
        turnId: 0,
        toolUseId: 'tool_abc',
        isError: true,
        errorMessage: 'File not found',
      );

      expect(event.isError, isTrue);
      expect(event.errorMessage, equals('File not found'));
    });
  });

  group('CodingAgentTurnEndEvent', () {
    test('stores success status', () {
      final event = CodingAgentTurnEndEvent(
        sessionId: 'sess_123',
        turnId: 0,
        status: CodingAgentTurnStatus.success,
      );

      expect(event.status, equals(CodingAgentTurnStatus.success));
      expect(event.usage, isNull);
      expect(event.durationMs, isNull);
      expect(event.errorMessage, isNull);
    });

    test('stores error status with message', () {
      final event = CodingAgentTurnEndEvent(
        sessionId: 'sess_123',
        turnId: 0,
        status: CodingAgentTurnStatus.error,
        errorMessage: 'API rate limit exceeded',
      );

      expect(event.status, equals(CodingAgentTurnStatus.error));
      expect(event.errorMessage, equals('API rate limit exceeded'));
    });

    test('stores usage statistics', () {
      final usage = CodingAgentUsage(inputTokens: 100, outputTokens: 200);
      final event = CodingAgentTurnEndEvent(
        sessionId: 'sess_123',
        turnId: 0,
        status: CodingAgentTurnStatus.success,
        usage: usage,
        durationMs: 5000,
      );

      expect(event.usage, equals(usage));
      expect(event.durationMs, equals(5000));
    });
  });

  group('CodingAgentErrorEvent', () {
    test('stores error details', () {
      final event = CodingAgentErrorEvent(
        sessionId: 'sess_123',
        turnId: 0,
        code: 'RATE_LIMIT',
        message: 'Too many requests',
      );

      expect(event.code, equals('RATE_LIMIT'));
      expect(event.message, equals('Too many requests'));
    });

    test('code is optional', () {
      final event = CodingAgentErrorEvent(
        sessionId: 'sess_123',
        turnId: 0,
        message: 'Unknown error',
      );

      expect(event.code, isNull);
    });
  });

  group('CodingAgentUnknownEvent', () {
    test('stores unknown event data', () {
      final event = CodingAgentUnknownEvent(
        sessionId: 'sess_123',
        turnId: 0,
        originalType: 'custom_event',
        data: {'key': 'value', 'count': 42},
      );

      expect(event.originalType, equals('custom_event'));
      expect(event.data, equals({'key': 'value', 'count': 42}));
    });
  });

  group('Event sealed class', () {
    test('events are sealed and can be pattern matched', () {
      final events = <CodingAgentEvent>[
        CodingAgentInitEvent(sessionId: 's', turnId: 0),
        CodingAgentTextEvent(sessionId: 's', turnId: 0, text: 'hi'),
        CodingAgentThinkingEvent(sessionId: 's', turnId: 0, thinking: 'hmm'),
        CodingAgentToolUseEvent(sessionId: 's', turnId: 0, toolUseId: 't', toolName: 'Read', input: {}),
        CodingAgentToolResultEvent(sessionId: 's', turnId: 0, toolUseId: 't'),
        CodingAgentTurnEndEvent(sessionId: 's', turnId: 0, status: CodingAgentTurnStatus.success),
        CodingAgentErrorEvent(sessionId: 's', turnId: 0, message: 'err'),
        CodingAgentUnknownEvent(sessionId: 's', turnId: 0, originalType: 'x', data: {}),
      ];

      for (final event in events) {
        // Exhaustive switch should compile
        final result = switch (event) {
          CodingAgentInitEvent() => 'init',
          CodingAgentTextEvent() => 'text',
          CodingAgentThinkingEvent() => 'thinking',
          CodingAgentToolUseEvent() => 'tool_use',
          CodingAgentToolResultEvent() => 'tool_result',
          CodingAgentTurnEndEvent() => 'turn_end',
          CodingAgentErrorEvent() => 'error',
          CodingAgentUnknownEvent() => 'unknown',
        };
        expect(result, isNotEmpty);
      }
    });
  });
}
