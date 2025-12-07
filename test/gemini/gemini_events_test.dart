import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/gemini/gemini_events.dart';

void main() {
  group('GeminiEvent.fromJson', () {
    test('parses init event', () {
      final json = {
        'type': 'init',
        'session_id': 'sess_abc123',
        'timestamp': '2025-01-01T10:00:00.000Z',
        'model': 'gemini-2.0-flash-exp',
      };

      final event = GeminiEvent.fromJson(json, '', 1);

      expect(event, isA<GeminiInitEvent>());
      final initEvent = event as GeminiInitEvent;
      expect(initEvent.sessionId, 'sess_abc123');
      expect(initEvent.model, 'gemini-2.0-flash-exp');
      expect(initEvent.turnId, 1);
    });

    test('parses user message event', () {
      final json = {
        'type': 'message',
        'session_id': 'sess_abc123',
        'timestamp': '2025-01-01T10:00:01.000Z',
        'role': 'user',
        'content': 'Analyze the auth module',
        'delta': false,
      };

      final event = GeminiEvent.fromJson(json, 'sess_abc123', 1);

      expect(event, isA<GeminiMessageEvent>());
      final msgEvent = event as GeminiMessageEvent;
      expect(msgEvent.role, 'user');
      expect(msgEvent.content, 'Analyze the auth module');
      expect(msgEvent.delta, isFalse);
    });

    test('parses assistant message event', () {
      final json = {
        'type': 'message',
        'session_id': 'sess_abc123',
        'timestamp': '2025-01-01T10:00:02.000Z',
        'role': 'assistant',
        'content': 'I will analyze the authentication module.',
        'delta': false,
      };

      final event = GeminiEvent.fromJson(json, 'sess_abc123', 1);

      expect(event, isA<GeminiMessageEvent>());
      final msgEvent = event as GeminiMessageEvent;
      expect(msgEvent.role, 'assistant');
      expect(msgEvent.content, 'I will analyze the authentication module.');
    });

    test('parses assistant message with delta streaming', () {
      final json = {
        'type': 'message',
        'session_id': 'sess_abc123',
        'role': 'assistant',
        'content': 'I will',
        'delta': true,
      };

      final event = GeminiEvent.fromJson(json, 'sess_abc123', 1);

      expect(event, isA<GeminiMessageEvent>());
      final msgEvent = event as GeminiMessageEvent;
      expect(msgEvent.delta, isTrue);
      expect(msgEvent.content, 'I will');
    });

    test('parses tool_use event', () {
      final json = {
        'type': 'tool_use',
        'timestamp': '2025-01-01T10:00:03.000Z',
        'tool_name': 'Bash',
        'tool_id': 'bash_001',
        'parameters': {'command': 'cat src/auth.ts'},
      };

      final event = GeminiEvent.fromJson(json, 'sess_abc123', 2);

      expect(event, isA<GeminiToolUseEvent>());
      final toolUseEvent = event as GeminiToolUseEvent;
      expect(toolUseEvent.toolUse.toolName, 'Bash');
      expect(toolUseEvent.toolUse.toolId, 'bash_001');
      expect(toolUseEvent.toolUse.parameters['command'], 'cat src/auth.ts');
    });

    test('parses tool_result event with success', () {
      final json = {
        'type': 'tool_result',
        'timestamp': '2025-01-01T10:00:04.000Z',
        'tool_id': 'bash_001',
        'status': 'success',
        'output': 'export function login() { ... }',
      };

      final event = GeminiEvent.fromJson(json, 'sess_abc123', 2);

      expect(event, isA<GeminiToolResultEvent>());
      final resultEvent = event as GeminiToolResultEvent;
      expect(resultEvent.toolResult.toolId, 'bash_001');
      expect(resultEvent.toolResult.status, 'success');
      expect(resultEvent.toolResult.output, 'export function login() { ... }');
    });

    test('parses tool_result event with error', () {
      final json = {
        'type': 'tool_result',
        'timestamp': '2025-01-01T10:00:04.000Z',
        'tool_id': 'bash_001',
        'status': 'error',
        'error': {'type': 'execution_failed', 'message': 'Command not found'},
      };

      final event = GeminiEvent.fromJson(json, 'sess_abc123', 2);

      expect(event, isA<GeminiToolResultEvent>());
      final resultEvent = event as GeminiToolResultEvent;
      expect(resultEvent.toolResult.status, 'error');
      expect(resultEvent.toolResult.error!['type'], 'execution_failed');
    });

    test('parses result event with success', () {
      final json = {
        'type': 'result',
        'timestamp': '2025-01-01T10:30:00.000Z',
        'status': 'success',
        'stats': {
          'totalTokens': 350,
          'inputTokens': 100,
          'outputTokens': 250,
          'durationMs': 5000,
          'toolCalls': 2,
        },
      };

      final event = GeminiEvent.fromJson(json, 'sess_abc123', 3);

      expect(event, isA<GeminiResultEvent>());
      final resultEvent = event as GeminiResultEvent;
      expect(resultEvent.status, 'success');
      expect(resultEvent.stats, isNotNull);
      expect(resultEvent.stats!.totalTokens, 350);
      expect(resultEvent.stats!.inputTokens, 100);
      expect(resultEvent.stats!.outputTokens, 250);
      expect(resultEvent.stats!.durationMs, 5000);
      expect(resultEvent.stats!.toolCalls, 2);
    });

    test('parses result event with error', () {
      final json = {
        'type': 'result',
        'timestamp': '2025-01-01T10:30:00.000Z',
        'status': 'error',
        'error': {
          'code': 'EXECUTION_FAILED',
          'message': 'Tool execution timed out',
        },
      };

      final event = GeminiEvent.fromJson(json, 'sess_abc123', 3);

      expect(event, isA<GeminiResultEvent>());
      final resultEvent = event as GeminiResultEvent;
      expect(resultEvent.status, 'error');
      expect(resultEvent.error!['code'], 'EXECUTION_FAILED');
    });

    test('parses result event with cancelled status', () {
      final json = {'type': 'result', 'status': 'cancelled'};

      final event = GeminiEvent.fromJson(json, 'sess_abc123', 3);

      expect(event, isA<GeminiResultEvent>());
      final resultEvent = event as GeminiResultEvent;
      expect(resultEvent.status, 'cancelled');
    });

    test('parses error event', () {
      final json = {
        'type': 'error',
        'error': {
          'code': 'INVALID_CHUNK',
          'message': 'Stream ended with invalid chunk',
        },
      };

      final event = GeminiEvent.fromJson(json, 'sess_abc123', 2);

      expect(event, isA<GeminiErrorEvent>());
      final errorEvent = event as GeminiErrorEvent;
      expect(errorEvent.code, 'INVALID_CHUNK');
      expect(errorEvent.message, 'Stream ended with invalid chunk');
    });

    test('parses retry event', () {
      final json = {
        'type': 'retry',
        'attempt': 2,
        'max_attempts': 3,
        'delay_ms': 1000,
      };

      final event = GeminiEvent.fromJson(json, 'sess_abc123', 2);

      expect(event, isA<GeminiRetryEvent>());
      final retryEvent = event as GeminiRetryEvent;
      expect(retryEvent.attempt, 2);
      expect(retryEvent.maxAttempts, 3);
      expect(retryEvent.delayMs, 1000);
    });

    test('parses unknown event type gracefully', () {
      final json = {'type': 'future_event_type', 'some_field': 'some_value'};

      final event = GeminiEvent.fromJson(json, 'sess_abc123', 1);

      expect(event, isA<GeminiUnknownEvent>());
      final unknownEvent = event as GeminiUnknownEvent;
      expect(unknownEvent.type, 'future_event_type');
      expect(unknownEvent.data['some_field'], 'some_value');
    });

    test('handles missing optional fields', () {
      final json = {'type': 'init', 'session_id': 'sess_abc123'};

      final event = GeminiEvent.fromJson(json, '', 1);

      expect(event, isA<GeminiInitEvent>());
      final initEvent = event as GeminiInitEvent;
      expect(initEvent.sessionId, 'sess_abc123');
      expect(initEvent.model, '');
    });

    test('preserves sessionId and turnId across all event types', () {
      final events = [
        {'type': 'init', 'session_id': 's1'},
        {'type': 'message', 'role': 'user', 'content': 'hi'},
        {
          'type': 'tool_use',
          'tool_name': 'Bash',
          'tool_id': 't1',
          'parameters': {},
        },
        {'type': 'tool_result', 'tool_id': 't1', 'status': 'success'},
        {'type': 'result', 'status': 'success'},
        {
          'type': 'error',
          'error': {'code': 'ERR', 'message': 'msg'},
        },
        {'type': 'retry', 'attempt': 1, 'max_attempts': 3, 'delay_ms': 100},
      ];

      for (final eventJson in events) {
        final event = GeminiEvent.fromJson(eventJson, 'sess_test', 42);
        expect(
          event.turnId,
          42,
          reason: 'Event type ${eventJson['type']} should preserve turnId',
        );
      }
    });
  });

  group('GeminiEvent properties', () {
    test('all events have sessionId, turnId, and timestamp', () {
      final json = {
        'type': 'init',
        'session_id': 'sess_test',
        'timestamp': '2025-01-01T12:00:00.000Z',
      };

      final event = GeminiEvent.fromJson(json, 'sess_test', 7);

      expect(event.sessionId, 'sess_test');
      expect(event.turnId, 7);
      expect(event.timestamp, isA<DateTime>());
    });
  });
}
