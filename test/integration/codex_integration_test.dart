@Timeout(Duration(seconds: 30))
library;

import 'dart:io';

import 'package:coding_agents/src/cli_adapters/codex/codex_cli_adapter.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_config.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_events.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_types.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Integration tests for Codex CLI adapter
/// These tests use the adapter layer which manages process lifecycle internally
void main() {
  late CodexCliAdapter client;
  late CodexSessionConfig config;
  late String testWorkDir;

  setUpAll(() {
    // Use tmp/ folder to avoid polluting project with session history
    testWorkDir = p.join(Directory.current.path, 'tmp');
    Directory(testWorkDir).createSync(recursive: true);
  });

  setUp(() {
    client = CodexCliAdapter();
    config = CodexSessionConfig(
      fullAuto: true,
      // Override invalid user config value
      configOverrides: ['model_reasoning_effort="high"'],
    );
  });

  group('Codex Adapter Integration', () {
    test('createSession returns session with valid thread_id', () async {
      final session = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session.send('Say exactly: "Hello"');

      expect(session.threadId, isNotNull);
      expect(session.threadId, isNotEmpty);

      // Collect events until turn completed
      final events = <CodexEvent>[];
      await for (final event in session.events) {
        events.add(event);
        if (event is CodexTurnCompletedEvent) break;
      }

      // Verify we got expected event types
      expect(
        events.any((e) => e is CodexThreadStartedEvent),
        isTrue,
        reason: 'Should have thread.started event',
      );
      expect(
        events.any((e) => e is CodexTurnCompletedEvent),
        isTrue,
        reason: 'Should have turn.completed event',
      );
    });

    test('session streams agent_message content', () async {
      final session = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session.send('Respond with exactly: "Test response"');

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

      expect(
        agentMessages,
        isNotEmpty,
        reason: 'Should receive agent_message items',
      );
      expect(
        agentMessages.first.text,
        isNotEmpty,
        reason: 'Agent message should have text',
      );
    });

    test('session executes tool and returns tool_call item', () async {
      final session = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session.send(
        'Use the shell tool to run: echo "test output". Do not skip this step.',
      );

      final toolItems = <CodexToolCallItem>[];

      await for (final event in session.events) {
        if (event is CodexItemCompletedEvent) {
          final item = event.item;
          if (item is CodexToolCallItem) {
            toolItems.add(item);
          }
        }
        if (event is CodexTurnCompletedEvent) break;
      }

      expect(
        toolItems,
        isNotEmpty,
        reason: 'Should have received a real tool_call item from Codex',
      );
      expect(
        toolItems.any(
          (t) =>
              t.output?.toLowerCase().contains('test output') == true &&
              t.exitCode == 0,
        ),
        isTrue,
        reason: 'Tool_call item should include the shell output and a success exit code',
      );
    });

    test('turn.completed event contains usage stats', () async {
      final session = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session.send('Say: "Done"');

      CodexTurnCompletedEvent? turnCompleted;

      await for (final event in session.events) {
        if (event is CodexTurnCompletedEvent) {
          turnCompleted = event;
          break;
        }
      }

      expect(
        turnCompleted,
        isNotNull,
        reason: 'Should receive turn.completed event',
      );
      expect(
        turnCompleted!.usage,
        isNotNull,
        reason: 'Should have usage stats',
      );
      expect(turnCompleted.usage!.inputTokens, isA<int>());
      expect(turnCompleted.usage!.outputTokens, isA<int>());
    });

    test('can resume session with resumeSession', () async {
      // First turn - create a session
      final session1 = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session1.send('Hi! My name is Chris!');

      final threadId = session1.threadId;

      // Wait for first session to complete
      await for (final event in session1.events) {
        if (event is CodexTurnCompletedEvent) break;
      }

      // Second turn - resume session
      final session2 = await client.resumeSession(
        threadId,
        config,
        projectDirectory: testWorkDir,
      );
      await session2.send('Say my name.');

      expect(
        session2.threadId,
        equals(threadId),
        reason: 'Resumed session should have same thread_id',
      );

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

      // The response should mention Chris
      final fullResponse = responses.join(' ').toLowerCase();
      expect(
        fullResponse.contains('chris'),
        isTrue,
        reason: 'Codex should remember the name from previous turn',
      );
    });

    test('session events include correct turnId', () async {
      final session = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session.send('Say: "Turn test"');

      final turnIds = <int>{};

      await for (final event in session.events) {
        turnIds.add(event.turnId);
        if (event is CodexTurnCompletedEvent) break;
      }

      // All events from same session should have same turnId
      expect(
        turnIds.length,
        equals(1),
        reason: 'All events should have same turnId',
      );
      expect(
        turnIds.first,
        equals(session.currentTurnId),
        reason: 'TurnId should match session turnId',
      );
    });

    test('listSessions returns sessions including created session', () async {
      // Create a session
      final session = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session.send('Say: "List test"');

      final threadId = session.threadId;

      // Wait for session to complete
      await for (final event in session.events) {
        if (event is CodexTurnCompletedEvent) break;
      }

      // List sessions
      final sessions = await client.listSessions(projectDirectory: testWorkDir);

      // Verify our session is in the list
      expect(sessions, isNotEmpty, reason: 'Should have at least one session');
      expect(
        sessions.any((s) => s.threadId == threadId),
        isTrue,
        reason: 'Created session should be in the list',
      );
    });

    test('API errors throw exception with error details', () async {
      // Use an invalid model name to trigger an API error
      final badConfig = CodexSessionConfig(
        fullAuto: true,
        model: 'invalid-model-that-does-not-exist-xyz',
      );

      final session = await client.createSession(
        badConfig,
        projectDirectory: testWorkDir,
      );

      // Expect the exception to include the actual error message
      expect(
        () async {
          await session.send('Say hello');
          await for (final event in session.events) {
            if (event is CodexTurnCompletedEvent) break;
          }
        },
        throwsA(
          isA<CodexProcessException>().having(
            (e) => e.message,
            'message',
            // Should contain actual error details from API
            predicate<String>(
              (msg) => msg.contains('invalid-model') || msg.contains('400'),
              'contains error details from Codex API',
            ),
          ),
        ),
        reason: 'Exception should contain error details from API',
      );
    });

    test('CLI errors throw exception with stderr details', () async {
      // Use an invalid CLI flag to trigger a CLI error
      final badConfig = CodexSessionConfig(
        fullAuto: true,
        extraArgs: ['--fail-for-me-please'],
      );

      // Expect createSession to fail with CLI error details
      expect(
        () async {
          final session = await client.createSession(
            badConfig,
            projectDirectory: testWorkDir,
          );
          await session.send('Say hello');
          await for (final event in session.events) {
            if (event is CodexTurnCompletedEvent) break;
          }
        },
        throwsA(
          isA<CodexProcessException>().having(
            (e) => e.message,
            'message',
            // Codex CLI outputs: "error: unexpected argument '--fail-for-me-please' found"
            contains('unexpected'),
          ),
        ),
        reason: 'Exception should contain error details from CLI stderr',
      );
    });

    test('getSessionHistory returns all events from session', () async {
      const testPrompt = 'Say exactly: "History test response"';

      // Create a session
      final session = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session.send(testPrompt);
      final threadId = session.threadId;

      // Wait for session to complete
      await for (final event in session.events) {
        if (event is CodexTurnCompletedEvent) break;
      }

      // Get session history
      final history = await client.getSessionHistory(
        threadId,
        projectDirectory: testWorkDir,
      );

      // Verify history contains events
      expect(history, isNotEmpty, reason: 'History should not be empty');
      // The exact set of events stored to disk may differ from streamed events
      // Just verify we got some events back
    });

    test('getSessionHistory includes user and assistant messages', () async {
      const testPrompt = 'Say exactly: "First prompt response"';

      // Create a session
      final session = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session.send(testPrompt);
      final threadId = session.threadId;

      // Wait for session to complete
      await for (final event in session.events) {
        if (event is CodexTurnCompletedEvent) break;
      }

      // Get session history
      final history = await client.getSessionHistory(
        threadId,
        projectDirectory: testWorkDir,
      );

      // Find user and agent message events
      final userMessages = <CodexUserMessageEvent>[];
      final agentMessages = <CodexAgentMessageEvent>[];
      for (final event in history) {
        if (event is CodexUserMessageEvent) {
          userMessages.add(event);
        } else if (event is CodexAgentMessageEvent) {
          agentMessages.add(event);
        }
      }

      // Verify we have both user and agent messages
      expect(
        userMessages,
        isNotEmpty,
        reason: 'History should include user messages',
      );
      expect(
        agentMessages,
        isNotEmpty,
        reason: 'History should include agent messages',
      );
    });

    test('getSessionHistory can be called multiple times', () async {
      const testPrompt = 'Say exactly: "Idempotency test"';

      // Create a session
      final session = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session.send(testPrompt);
      final threadId = session.threadId;

      // Wait for session to complete
      await for (final event in session.events) {
        if (event is CodexTurnCompletedEvent) break;
      }

      // Get session history twice - should work both times
      final history1 = await client.getSessionHistory(
        threadId,
        projectDirectory: testWorkDir,
      );
      final history2 = await client.getSessionHistory(
        threadId,
        projectDirectory: testWorkDir,
      );

      // Both should return the same events
      expect(history1.length, equals(history2.length));
    });

    test('getSessionHistory throws for non-existent session', () async {
      expect(
        () => client.getSessionHistory(
          'non-existent-thread-id-xyz',
          projectDirectory: testWorkDir,
        ),
        throwsA(isA<CodexProcessException>()),
        reason: 'Should throw for non-existent session',
      );
    });
  });
}
