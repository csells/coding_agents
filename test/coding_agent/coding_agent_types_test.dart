import 'package:coding_agents/src/coding_agent/coding_agent_types.dart';
import 'package:test/test.dart';

void main() {
  group('CodingAgentUsage', () {
    test('calculates totalTokens correctly', () {
      final usage = CodingAgentUsage(
        inputTokens: 100,
        outputTokens: 50,
      );

      expect(usage.totalTokens, equals(150));
    });

    test('handles optional fields', () {
      final usage = CodingAgentUsage(
        inputTokens: 100,
        outputTokens: 50,
        cachedInputTokens: 25,
        cacheCreationInputTokens: 10,
        cacheReadInputTokens: 15,
      );

      expect(usage.cachedInputTokens, equals(25));
      expect(usage.cacheCreationInputTokens, equals(10));
      expect(usage.cacheReadInputTokens, equals(15));
    });

    test('optional fields are null by default', () {
      final usage = CodingAgentUsage(
        inputTokens: 100,
        outputTokens: 50,
      );

      expect(usage.cachedInputTokens, isNull);
      expect(usage.cacheCreationInputTokens, isNull);
      expect(usage.cacheReadInputTokens, isNull);
    });
  });

  group('CodingAgentSessionInfo', () {
    test('stores all required fields', () {
      final now = DateTime.now();
      final info = CodingAgentSessionInfo(
        sessionId: 'sess_123',
        createdAt: now,
        lastUpdatedAt: now,
      );

      expect(info.sessionId, equals('sess_123'));
      expect(info.createdAt, equals(now));
      expect(info.lastUpdatedAt, equals(now));
    });

    test('stores optional fields', () {
      final now = DateTime.now();
      final info = CodingAgentSessionInfo(
        sessionId: 'sess_123',
        createdAt: now,
        lastUpdatedAt: now,
        projectDirectory: '/path/to/project',
        gitBranch: 'main',
        messageCount: 5,
      );

      expect(info.projectDirectory, equals('/path/to/project'));
      expect(info.gitBranch, equals('main'));
      expect(info.messageCount, equals(5));
    });

    test('optional fields are null by default', () {
      final now = DateTime.now();
      final info = CodingAgentSessionInfo(
        sessionId: 'sess_123',
        createdAt: now,
        lastUpdatedAt: now,
      );

      expect(info.projectDirectory, isNull);
      expect(info.gitBranch, isNull);
      expect(info.messageCount, isNull);
    });
  });

  group('CodingAgentTurnStatus', () {
    test('has all expected values', () {
      expect(CodingAgentTurnStatus.values, hasLength(3));
      expect(CodingAgentTurnStatus.values, contains(CodingAgentTurnStatus.success));
      expect(CodingAgentTurnStatus.values, contains(CodingAgentTurnStatus.error));
      expect(CodingAgentTurnStatus.values, contains(CodingAgentTurnStatus.cancelled));
    });
  });
}
