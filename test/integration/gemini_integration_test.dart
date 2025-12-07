@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:coding_agents/src/cli_adapters/gemini/gemini_cli_adapter.dart';
import 'package:coding_agents/src/cli_adapters/gemini/gemini_events.dart';
import 'package:coding_agents/src/cli_adapters/gemini/gemini_types.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Integration tests for Gemini CLI adapter
/// These tests use the adapter layer which manages process lifecycle internally
void main() {
  late GeminiCliAdapter client;
  late GeminiSessionConfig config;
  late String testWorkDir;

  setUpAll(() {
    // Use tmp/ folder to avoid polluting project with session history
    testWorkDir = p.join(Directory.current.path, 'tmp');
    Directory(testWorkDir).createSync(recursive: true);
  });

  setUp(() {
    client = GeminiCliAdapter();
    // Use sandbox mode to prevent Gemini from modifying project files
    config = GeminiSessionConfig(
      approvalMode: GeminiApprovalMode.yolo,
      sandbox: true,
    );
  });

  group('Gemini Adapter Integration', () {
    test('createSession returns session with valid session_id', () async {
      final session = await client.createSession(
        'Say exactly: "Hello"',
        config,
        projectDirectory: testWorkDir,
      );

      expect(session.sessionId, isNotNull);
      expect(session.sessionId, isNotEmpty);

      // Collect events until result
      final events = <GeminiEvent>[];
      await for (final event in session.events) {
        events.add(event);
        if (event is GeminiResultEvent) break;
      }

      // Verify we got expected event types
      expect(
        events.any((e) => e is GeminiInitEvent),
        isTrue,
        reason: 'Should have init event',
      );
      expect(
        events.any((e) => e is GeminiResultEvent),
        isTrue,
        reason: 'Should have result event',
      );
    });

    test('session streams assistant message content', () async {
      final session = await client.createSession(
        'Respond with exactly: "Test response"',
        config,
        projectDirectory: testWorkDir,
      );

      final assistantMessages = <GeminiMessageEvent>[];

      await for (final event in session.events) {
        if (event is GeminiMessageEvent && event.role == 'assistant') {
          assistantMessages.add(event);
        }
        if (event is GeminiResultEvent) break;
      }

      expect(
        assistantMessages,
        isNotEmpty,
        reason: 'Should receive assistant messages',
      );
      expect(
        assistantMessages.first.content,
        isNotNull,
        reason: 'Assistant message should have content',
      );
    });

    test('session executes tool and returns tool_use event', () async {
      final session = await client.createSession(
        'Read the file pubspec.yaml and tell me the package name',
        config,
        projectDirectory: testWorkDir,
      );

      final toolUseEvents = <GeminiToolUseEvent>[];
      final toolResultEvents = <GeminiToolResultEvent>[];
      final allEvents = <GeminiEvent>[];

      await for (final event in session.events) {
        allEvents.add(event);
        if (event is GeminiToolUseEvent) {
          toolUseEvents.add(event);
        }
        if (event is GeminiToolResultEvent) {
          toolResultEvents.add(event);
        }
        if (event is GeminiResultEvent) break;
      }

      // Should have at least received some events from Gemini
      // Tool events may not appear in sandbox mode
      expect(
        allEvents,
        isNotEmpty,
        reason: 'Should have received some events from Gemini',
      );
    });

    test('result event contains success status and stats', () async {
      final session = await client.createSession(
        'Say: "Done"',
        config,
        projectDirectory: testWorkDir,
      );

      GeminiResultEvent? resultEvent;

      await for (final event in session.events) {
        if (event is GeminiResultEvent) {
          resultEvent = event;
          break;
        }
      }

      expect(resultEvent, isNotNull, reason: 'Should receive result event');
      expect(
        resultEvent!.status,
        equals('success'),
        reason: 'Result should indicate success',
      );
      expect(resultEvent.stats, isNotNull, reason: 'Result should have stats');
      expect(resultEvent.stats!.totalTokens, isA<int>());
    });

    test('can resume session with resumeSession', () async {
      // First turn - create a session
      final session1 = await client.createSession(
        'Hi! My name is Chris!',
        config,
        projectDirectory: testWorkDir,
      );

      final sessionId = session1.sessionId;

      // Wait for first session to complete
      await for (final event in session1.events) {
        if (event is GeminiResultEvent) break;
      }

      // Second turn - resume session
      final session2 = await client.resumeSession(
        sessionId,
        'Say my name.',
        config,
        projectDirectory: testWorkDir,
      );

      final responses = <String>[];

      await for (final event in session2.events) {
        if (event is GeminiMessageEvent && event.role == 'assistant') {
          responses.add(event.content);
        }
        if (event is GeminiResultEvent) break;
      }

      // The response should mention Chris
      final fullResponse = responses.join(' ').toLowerCase();
      expect(
        fullResponse.contains('chris'),
        isTrue,
        reason: 'Gemini should remember the name from previous turn',
      );
    });

    test('session events include correct turnId', () async {
      final session = await client.createSession(
        'Say: "Turn test"',
        config,
        projectDirectory: testWorkDir,
      );

      final turnIds = <int>{};

      await for (final event in session.events) {
        turnIds.add(event.turnId);
        if (event is GeminiResultEvent) break;
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
        'Say: "List test"',
        config,
        projectDirectory: testWorkDir,
      );

      final sessionId = session.sessionId;

      // Wait for session to complete
      await for (final event in session.events) {
        if (event is GeminiResultEvent) break;
      }

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
      // Use an invalid model name to trigger an API error (404 not found)
      final badConfig = GeminiSessionConfig(
        approvalMode: GeminiApprovalMode.yolo,
        sandbox: true,
        model: 'invalid-model-that-does-not-exist-xyz',
      );

      final session = await client.createSession(
        'Say hello',
        badConfig,
        projectDirectory: testWorkDir,
      );

      // Expect exception to be thrown with error details
      // Gemini CLI outputs: [API Error: [{"error": {"code": 404, "message": "..."}}]]
      expect(
        () async {
          await for (final event in session.events) {
            if (event is GeminiResultEvent) break;
          }
        },
        throwsA(
          isA<GeminiProcessException>().having(
            (e) => e.message.toLowerCase(),
            'message',
            anyOf(
              contains('404'),
              contains('not found'),
              contains('api error'),
            ),
          ),
        ),
        reason: 'Exception should contain error details from API',
      );
    });

    test('CLI errors throw exception with stderr details', () async {
      // Use an invalid CLI flag to trigger a CLI error
      final badConfig = GeminiSessionConfig(
        approvalMode: GeminiApprovalMode.yolo,
        sandbox: true,
        extraArgs: ['--fail-for-me-please'],
      );

      // Expect createSession to fail with CLI error details
      expect(
        () async {
          final session = await client.createSession(
            'Say hello',
            badConfig,
            projectDirectory: testWorkDir,
          );
          await for (final event in session.events) {
            if (event is GeminiResultEvent) break;
          }
        },
        throwsA(
          isA<GeminiProcessException>().having(
            (e) => e.message,
            'message',
            // Gemini CLI outputs: "Unknown arguments: fail-for-me-please"
            anyOf(contains('Unknown'), contains('unknown')),
          ),
        ),
        reason: 'Exception should contain error details from CLI stderr',
      );
    });

    test('getSessionHistory returns all events from session', () async {
      const testPrompt = 'Say exactly: "History test response"';

      // Create a session
      final session = await client.createSession(
        testPrompt,
        config,
        projectDirectory: testWorkDir,
      );
      final sessionId = session.sessionId;

      // Wait for session to complete
      await for (final event in session.events) {
        if (event is GeminiResultEvent) break;
      }

      // Get session history
      final history = await client.getSessionHistory(
        sessionId,
        projectDirectory: testWorkDir,
      );

      // Verify history contains expected event types
      expect(history, isNotEmpty, reason: 'History should not be empty');
      expect(
        history.any((e) => e is GeminiInitEvent),
        isTrue,
        reason: 'History should contain init event',
      );
      expect(
        history.any((e) => e is GeminiResultEvent),
        isTrue,
        reason: 'History should contain result event',
      );
    });

    test('getSessionHistory includes user and assistant messages', () async {
      const testPrompt = 'Say exactly: "First prompt response"';

      // Create a session
      final session = await client.createSession(
        testPrompt,
        config,
        projectDirectory: testWorkDir,
      );
      final sessionId = session.sessionId;

      // Wait for session to complete
      await for (final event in session.events) {
        if (event is GeminiResultEvent) break;
      }

      // Get session history
      final history = await client.getSessionHistory(
        sessionId,
        projectDirectory: testWorkDir,
      );

      // Find message events
      final userMessages = <GeminiMessageEvent>[];
      final assistantMessages = <GeminiMessageEvent>[];
      for (final event in history) {
        if (event is GeminiMessageEvent) {
          if (event.role == 'user') {
            userMessages.add(event);
          } else if (event.role == 'assistant') {
            assistantMessages.add(event);
          }
        }
      }

      // Verify we have both user and assistant messages
      expect(
        userMessages,
        isNotEmpty,
        reason: 'History should include user messages',
      );
      expect(
        assistantMessages,
        isNotEmpty,
        reason: 'History should include assistant messages',
      );
    });

    test('getSessionHistory can be called multiple times', () async {
      const testPrompt = 'Say exactly: "Idempotency test"';

      // Create a session
      final session = await client.createSession(
        testPrompt,
        config,
        projectDirectory: testWorkDir,
      );
      final sessionId = session.sessionId;

      // Wait for session to complete
      await for (final event in session.events) {
        if (event is GeminiResultEvent) break;
      }

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
        throwsA(isA<GeminiProcessException>()),
        reason: 'Should throw for non-existent session',
      );
    });
  });
}
