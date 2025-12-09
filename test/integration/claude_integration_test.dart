@Timeout(Duration(seconds: 30))
library;

import 'dart:io';

import 'package:coding_agents/src/cli_adapters/claude_code/claude_code_cli_adapter.dart';
import 'package:coding_agents/src/cli_adapters/claude_code/claude_config.dart';
import 'package:coding_agents/src/cli_adapters/claude_code/claude_events.dart';
import 'package:coding_agents/src/cli_adapters/claude_code/claude_types.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Integration tests for Claude Code CLI adapter
/// These tests use the adapter layer which manages process lifecycle internally
void main() {
  late ClaudeCodeCliAdapter client;
  late ClaudeSessionConfig config;
  late String testWorkDir;

  setUpAll(() {
    // Use tmp/ folder to avoid polluting project with session history
    testWorkDir = p.join(Directory.current.path, 'tmp');
    Directory(testWorkDir).createSync(recursive: true);
  });

  setUp(() {
    client = ClaudeCodeCliAdapter();
    config = ClaudeSessionConfig(
      permissionMode: ClaudePermissionMode.bypassPermissions,
      maxTurns: 1,
    );
  });

  group('Claude Adapter Integration', () {
    test('createSession returns session with valid session_id', () async {
      final session = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session.send('Say exactly: "Hello"');

      // Collect events until result
      final events = <ClaudeEvent>[];
      await for (final event in session.events) {
        events.add(event);
        if (event is ClaudeResultEvent) break;
      }

      // Session ID is populated after init event arrives
      expect(session.sessionId, isNotNull);
      expect(session.sessionId, isNotEmpty);

      // Verify we got expected event types
      expect(
        events.any((e) => e is ClaudeSystemEvent),
        isTrue,
        reason: 'Should have system init event',
      );
      expect(
        events.any((e) => e is ClaudeResultEvent),
        isTrue,
        reason: 'Should have result event',
      );
    });

    test('session streams assistant message content', () async {
      final session = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session.send('Respond with exactly: "Test response"');

      final assistantEvents = <ClaudeAssistantEvent>[];

      await for (final event in session.events) {
        if (event is ClaudeAssistantEvent) {
          assistantEvents.add(event);
        }
        if (event is ClaudeResultEvent) break;
      }

      expect(
        assistantEvents,
        isNotEmpty,
        reason: 'Should receive assistant messages',
      );
      expect(
        assistantEvents.first.content,
        isNotEmpty,
        reason: 'Assistant message should have content',
      );
    });

    test(
      'session executes tool and returns tool_use in assistant message',
      () async {
        final toolConfig = ClaudeSessionConfig(
          permissionMode: ClaudePermissionMode.bypassPermissions,
          maxTurns: 3,
        );

        final session = await client.createSession(
          toolConfig,
          projectDirectory: testWorkDir,
        );
        await session.send(
          'Read the file pubspec.yaml and tell me the package name',
        );

        final toolUseBlocks = <ClaudeToolUseBlock>[];
        final userEvents = <ClaudeUserEvent>[];

        await for (final event in session.events) {
          if (event is ClaudeAssistantEvent) {
            for (final block in event.content) {
              if (block is ClaudeToolUseBlock) {
                toolUseBlocks.add(block);
              }
            }
          }
          if (event is ClaudeUserEvent) {
            userEvents.add(event);
          }
          if (event is ClaudeResultEvent) break;
        }

        expect(
          toolUseBlocks,
          isNotEmpty,
          reason: 'Should have tool_use blocks for reading file',
        );

        // Verify Read tool was used
        final toolNames = toolUseBlocks.map((b) => b.name).toSet();
        expect(
          toolNames.contains('Read'),
          isTrue,
          reason: 'Should use Read tool to read pubspec.yaml',
        );
      },
    );

    test('permission handler is invoked in delegate mode', () async {
      var approvals = 0;
      final toolConfig = ClaudeSessionConfig(
        permissionMode: ClaudePermissionMode.defaultMode,
        permissionHandler: (request) async {
          approvals++;
          return ClaudeToolPermissionResponse(
            behavior: ClaudePermissionBehavior.allow,
          );
        },
        maxTurns: 2,
      );

      final session = await client.createSession(
        toolConfig,
        projectDirectory: testWorkDir,
      );
      await session.send(
        'Read the file pubspec.yaml and tell me the package name',
      );

      await for (final event in session.events) {
        if (event is ClaudeResultEvent) break;
      }

      expect(
        approvals,
        greaterThan(0),
        reason: 'Delegate permission handler should be invoked in non-yolo mode',
      );
    });

    test('result event contains success status', () async {
      final session = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session.send('Say: "Done"');

      ClaudeResultEvent? resultEvent;

      await for (final event in session.events) {
        if (event is ClaudeResultEvent) {
          resultEvent = event;
          break;
        }
      }

      expect(resultEvent, isNotNull, reason: 'Should receive result event');
      expect(
        resultEvent!.subtype,
        equals('success'),
        reason: 'Result should indicate success',
      );
      expect(
        resultEvent.sessionId,
        isNotNull,
        reason: 'Result should include session_id',
      );
    });

    test('can resume session with resumeSession', () async {
      // First turn - create a session
      final session1 = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session1.send('Hi! My name is Chris!');

      // Wait for first session to complete
      await for (final event in session1.events) {
        if (event is ClaudeResultEvent) break;
      }

      // Session ID is now available after events are collected
      final sessionId = session1.sessionId!;

      // Second turn - resume session
      final session2 = await client.resumeSession(
        sessionId,
        config,
        projectDirectory: testWorkDir,
      );
      await session2.send('Say my name.');

      final responses = <String>[];

      await for (final event in session2.events) {
        if (event is ClaudeAssistantEvent) {
          for (final block in event.content) {
            if (block is ClaudeTextBlock) {
              responses.add(block.text);
            }
          }
        }
        if (event is ClaudeResultEvent) break;
      }

      // Session ID should match after resumed session's events are collected
      expect(
        session2.sessionId,
        equals(sessionId),
        reason: 'Resumed session should have same ID',
      );

      // The response should mention Chris
      final fullResponse = responses.join(' ').toLowerCase();
      expect(
        fullResponse.contains('chris'),
        isTrue,
        reason: 'Claude should remember the name from previous turn',
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
        if (event is ClaudeResultEvent) break;
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

      // Wait for session to complete
      await for (final event in session.events) {
        if (event is ClaudeResultEvent) break;
      }

      // Session ID is now available after events are collected
      final sessionId = session.sessionId!;

      // List sessions
      final sessions = await client.listSessions(projectDirectory: testWorkDir);

      // Verify our session is in the list
      expect(sessions, isNotEmpty, reason: 'Should have at least one session');
      expect(
        sessions.any((s) => s.sessionId == sessionId),
        isTrue,
        reason: 'Created session should be in the list',
      );
    });

    test('API errors throw exception with error details', () async {
      // Use an invalid model name to trigger an API error
      final badConfig = ClaudeSessionConfig(
        permissionMode: ClaudePermissionMode.bypassPermissions,
        model: 'invalid-model-that-does-not-exist-xyz',
      );

      final session = await client.createSession(
        badConfig,
        projectDirectory: testWorkDir,
      );

      // Expect exception to be thrown with error details
      expect(
        () async {
          await session.send('Say hello');
          await for (final event in session.events) {
            if (event is ClaudeResultEvent) break;
          }
        },
        throwsA(
          isA<ClaudeProcessException>().having(
            (e) => e.message,
            'message',
            contains('invalid-model'),
          ),
        ),
        reason: 'Exception should contain error details from API',
      );
    });

    test('CLI errors throw exception with stderr details', () async {
      // Use an invalid CLI flag to trigger a CLI error
      final badConfig = ClaudeSessionConfig(
        permissionMode: ClaudePermissionMode.bypassPermissions,
        extraArgs: ['--fail-for-me-please'],
      );

      // With --input-format stream-json, CLI exits immediately on invalid args
      // The exception may be thrown at any point in the flow
      ClaudeProcessException? caughtException;

      final session = await client.createSession(
        badConfig,
        projectDirectory: testWorkDir,
      );

      // Listen for errors on the stream
      session.events.listen(
        (_) {},
        onError: (error) {
          if (error is ClaudeProcessException) {
            caughtException = error;
          }
        },
      );

      // Send prompt (may fail if process already dead)
      try {
        await session.send('Say hello');
      } on ClaudeProcessException catch (e) {
        caughtException = e;
      }

      // Wait for error to be delivered
      await Future.delayed(const Duration(milliseconds: 500));

      expect(
        caughtException,
        isNotNull,
        reason: 'Should throw ClaudeProcessException for CLI errors',
      );
      expect(
        caughtException!.message,
        contains('unknown'),
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

      // Wait for session to complete
      await for (final event in session.events) {
        if (event is ClaudeResultEvent) break;
      }

      // Session ID is now available after events are collected
      final sessionId = session.sessionId!;

      // Get session history
      final history = await client.getSessionHistory(
        sessionId,
        projectDirectory: testWorkDir,
      );

      // Verify history contains events
      expect(history, isNotEmpty, reason: 'History should not be empty');
      // History should contain at least some message-related events
      // The exact set of events stored to disk may differ from streamed events
      expect(
        history.any(
          (e) =>
              e is ClaudeUserEvent ||
              e is ClaudeAssistantEvent ||
              e is ClaudeSystemEvent,
        ),
        isTrue,
        reason: 'History should contain message-related events',
      );
    });

    test('getSessionHistory includes user and assistant messages', () async {
      const testPrompt = 'Say exactly: "First prompt test"';

      // Create a session
      final session = await client.createSession(
        config,
        projectDirectory: testWorkDir,
      );
      await session.send(testPrompt);

      // Wait for session to complete
      await for (final event in session.events) {
        if (event is ClaudeResultEvent) break;
      }

      // Session ID is now available after events are collected
      final sessionId = session.sessionId!;

      // Get session history
      final history = await client.getSessionHistory(
        sessionId,
        projectDirectory: testWorkDir,
      );

      // Find user and assistant events
      final userEvents = <ClaudeUserEvent>[];
      final assistantEvents = <ClaudeAssistantEvent>[];
      for (final event in history) {
        if (event is ClaudeUserEvent) {
          userEvents.add(event);
        } else if (event is ClaudeAssistantEvent) {
          assistantEvents.add(event);
        }
      }

      // Verify we have both user and assistant messages
      expect(
        userEvents,
        isNotEmpty,
        reason: 'History should include user messages',
      );
      expect(
        assistantEvents,
        isNotEmpty,
        reason: 'History should include assistant messages',
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

      // Wait for session to complete
      await for (final event in session.events) {
        if (event is ClaudeResultEvent) break;
      }

      // Session ID is now available after events are collected
      final sessionId = session.sessionId!;

      // Get session history twice - should work both times
      final history1 = await client.getSessionHistory(
        sessionId,
        projectDirectory: testWorkDir,
      );
      final history2 = await client.getSessionHistory(
        sessionId,
        projectDirectory: testWorkDir,
      );

      // Both should return the same events
      expect(history1.length, equals(history2.length));
    });

    test('getSessionHistory throws for non-existent session', () async {
      expect(
        () => client.getSessionHistory(
          'non-existent-session-id-xyz',
          projectDirectory: testWorkDir,
        ),
        throwsA(isA<ClaudeProcessException>()),
        reason: 'Should throw for non-existent session',
      );
    });
  });
}
