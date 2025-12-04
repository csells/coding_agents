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
    client = ClaudeCodeCliAdapter(cwd: testWorkDir);
    config = ClaudeSessionConfig(
      permissionMode: ClaudePermissionMode.bypassPermissions,
      maxTurns: 1,
    );
  });

  group('Claude Adapter Integration', () {
    test('createSession returns session with valid session_id', () async {
      final session = await client.createSession(
        'Say exactly: "Hello"',
        config,
      );

      expect(session.sessionId, isNotNull);
      expect(session.sessionId, isNotEmpty);

      // Collect events until result
      final events = <ClaudeEvent>[];
      await for (final event in session.events) {
        events.add(event);
        if (event is ClaudeResultEvent) break;
      }

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
        'Respond with exactly: "Test response"',
        config,
      );

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
          'Read the file pubspec.yaml and tell me the package name',
          toolConfig,
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

    test('result event contains success status', () async {
      final session = await client.createSession('Say: "Done"', config);

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
        'Remember this number: 42. Just say OK.',
        config,
      );

      final sessionId = session1.sessionId;

      // Wait for first session to complete
      await for (final event in session1.events) {
        if (event is ClaudeResultEvent) break;
      }

      // Second turn - resume session
      final session2 = await client.resumeSession(
        sessionId,
        'What number did I ask you to remember?',
        config,
      );

      expect(
        session2.sessionId,
        equals(sessionId),
        reason: 'Resumed session should have same ID',
      );

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

      // The response should mention 42
      final fullResponse = responses.join(' ');
      expect(
        fullResponse.contains('42'),
        isTrue,
        reason: 'Claude should remember the number from previous turn',
      );
    });

    test('session events include correct turnId', () async {
      final session = await client.createSession('Say: "Turn test"', config);

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
  });
}
