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
    client = GeminiCliAdapter(cwd: testWorkDir);
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

    test('result event contains success status and stats', () async {
      final session = await client.createSession('Say: "Done"', config);

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
        'Remember this number: 42. Just say OK.',
        config,
      );

      final sessionId = session1.sessionId;

      // Wait for first session to complete
      await for (final event in session1.events) {
        if (event is GeminiResultEvent) break;
      }

      // Second turn - resume session
      final session2 = await client.resumeSession(
        sessionId,
        'What number did I ask you to remember?',
        config,
      );

      final responses = <String>[];

      await for (final event in session2.events) {
        if (event is GeminiMessageEvent && event.role == 'assistant') {
          responses.add(event.content);
        }
        if (event is GeminiResultEvent) break;
      }

      // The response should mention 42
      final fullResponse = responses.join(' ');
      expect(
        fullResponse.contains('42'),
        isTrue,
        reason: 'Gemini should remember the number from previous turn',
      );
    });

    test('session events include correct turnId', () async {
      final session = await client.createSession('Say: "Turn test"', config);

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
  });
}
