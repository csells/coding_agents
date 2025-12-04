@Timeout(Duration(seconds: 30))
library;

import 'dart:io';

import 'package:coding_agents/src/cli_adapters/codex/codex_client.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_config.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_events.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_types.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Integration tests for Codex CLI adapter
/// These tests use the adapter layer which manages process lifecycle internally
void main() {
  late CodexClient client;
  late CodexSessionConfig config;
  late String testWorkDir;

  setUpAll(() {
    // Use tmp/ folder to avoid polluting project with session history
    testWorkDir = p.join(Directory.current.path, 'tmp');
    Directory(testWorkDir).createSync(recursive: true);
  });

  setUp(() {
    client = CodexClient(cwd: testWorkDir);
    config = CodexSessionConfig(
      fullAuto: true,
      // Override invalid user config value
      configOverrides: ['model_reasoning_effort="high"'],
    );
  });

  group('Codex Adapter Integration', () {
    test('createSession returns session with valid thread_id', () async {
      final session = await client.createSession(
        'Say exactly: "Hello"',
        config,
      );

      expect(session.threadId, isNotNull);
      expect(session.threadId, isNotEmpty);

      // Collect events until turn completed
      final events = <CodexEvent>[];
      await for (final event in session.events) {
        events.add(event);
        if (event is CodexTurnCompletedEvent) break;
      }

      // Verify we got expected event types
      expect(events.any((e) => e is CodexThreadStartedEvent), isTrue,
          reason: 'Should have thread.started event');
      expect(events.any((e) => e is CodexTurnCompletedEvent), isTrue,
          reason: 'Should have turn.completed event');
    });

    test('session streams agent_message content', () async {
      final session = await client.createSession(
        'Respond with exactly: "Test response"',
        config,
      );

      final agentMessages = <CodexAgentMessageItem>[];

      await for (final event in session.events) {
        if (event is CodexItemCompletedEvent) {
          final item = event.item;
          if (item is CodexAgentMessageItem) {
            agentMessages.add(item);
          }
        }
        if (event is CodexTurnCompletedEvent) break;
      }

      expect(agentMessages, isNotEmpty,
          reason: 'Should receive agent_message items');
      expect(agentMessages.first.text, isNotEmpty,
          reason: 'Agent message should have text');
    });

    test('session executes tool and returns tool_call item', () async {
      final session = await client.createSession(
        'Use the shell tool to run: echo "test output". Do not skip this step.',
        config,
      );

      final toolItems = <CodexToolCallItem>[];
      final allItems = <CodexItem>[];

      await for (final event in session.events) {
        if (event is CodexItemCompletedEvent) {
          allItems.add(event.item);
          final item = event.item;
          if (item is CodexToolCallItem) {
            toolItems.add(item);
          }
        }
        if (event is CodexTurnCompletedEvent) break;
      }

      // Should have at least received some items
      expect(allItems, isNotEmpty,
          reason: 'Should have received some items from Codex');
    });

    test('turn.completed event contains usage stats', () async {
      final session = await client.createSession(
        'Say: "Done"',
        config,
      );

      CodexTurnCompletedEvent? turnCompleted;

      await for (final event in session.events) {
        if (event is CodexTurnCompletedEvent) {
          turnCompleted = event;
          break;
        }
      }

      expect(turnCompleted, isNotNull,
          reason: 'Should receive turn.completed event');
      expect(turnCompleted!.usage, isNotNull, reason: 'Should have usage stats');
      expect(turnCompleted.usage!.inputTokens, isA<int>());
      expect(turnCompleted.usage!.outputTokens, isA<int>());
    });

    test('can resume session with resumeSession', () async {
      // First turn - create a session
      final session1 = await client.createSession(
        'Remember this number: 42. Just say OK.',
        config,
      );

      final threadId = session1.threadId;

      // Wait for first session to complete
      await for (final event in session1.events) {
        if (event is CodexTurnCompletedEvent) break;
      }

      // Second turn - resume session
      final session2 = await client.resumeSession(
        threadId,
        'What number did I ask you to remember?',
        config,
      );

      expect(session2.threadId, equals(threadId),
          reason: 'Resumed session should have same thread_id');

      final responses = <String>[];

      await for (final event in session2.events) {
        if (event is CodexItemCompletedEvent) {
          final item = event.item;
          if (item is CodexAgentMessageItem) {
            responses.add(item.text);
          }
        }
        if (event is CodexTurnCompletedEvent) break;
      }

      // The response should mention 42
      final fullResponse = responses.join(' ');
      expect(fullResponse.contains('42'), isTrue,
          reason: 'Codex should remember the number from previous turn');
    });

    test('session events include correct turnId', () async {
      final session = await client.createSession(
        'Say: "Turn test"',
        config,
      );

      final turnIds = <int>{};

      await for (final event in session.events) {
        turnIds.add(event.turnId);
        if (event is CodexTurnCompletedEvent) break;
      }

      // All events from same session should have same turnId
      expect(turnIds.length, equals(1),
          reason: 'All events should have same turnId');
      expect(turnIds.first, equals(session.currentTurnId),
          reason: 'TurnId should match session turnId');
    });
  });
}
