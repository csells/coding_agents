import 'package:coding_agents/src/coding_agent/coding_agents.dart';
import 'package:test/test.dart';

void main() {
  group('ClaudeCodingAgent', () {
    test('can be instantiated with default config', () {
      final agent = ClaudeCodingAgent();

      expect(agent.permissionMode, equals(ClaudePermissionMode.defaultMode));
      expect(agent.model, isNull);
      expect(agent.systemPrompt, isNull);
      expect(agent.appendSystemPrompt, isNull);
      expect(agent.maxTurns, isNull);
      expect(agent.allowedTools, isNull);
      expect(agent.disallowedTools, isNull);
    });

    test('can be instantiated with custom config', () {
      final agent = ClaudeCodingAgent(
        permissionMode: ClaudePermissionMode.bypassPermissions,
        model: 'claude-opus-4-5-20251101',
        systemPrompt: 'You are a code reviewer.',
        appendSystemPrompt: 'Be concise.',
        maxTurns: 10,
        allowedTools: ['Read', 'Write'],
        disallowedTools: ['Bash'],
      );

      expect(
          agent.permissionMode, equals(ClaudePermissionMode.bypassPermissions));
      expect(agent.model, equals('claude-opus-4-5-20251101'));
      expect(agent.systemPrompt, equals('You are a code reviewer.'));
      expect(agent.appendSystemPrompt, equals('Be concise.'));
      expect(agent.maxTurns, equals(10));
      expect(agent.allowedTools, equals(['Read', 'Write']));
      expect(agent.disallowedTools, equals(['Bash']));
    });

    test('implements CodingAgent interface', () {
      final agent = ClaudeCodingAgent();

      expect(agent, isA<CodingAgent>());
    });
  });

  group('ClaudePermissionMode', () {
    test('has all expected values', () {
      expect(ClaudePermissionMode.values, hasLength(4));
      expect(ClaudePermissionMode.values,
          contains(ClaudePermissionMode.defaultMode));
      expect(ClaudePermissionMode.values,
          contains(ClaudePermissionMode.acceptEdits));
      expect(ClaudePermissionMode.values,
          contains(ClaudePermissionMode.bypassPermissions));
      expect(
          ClaudePermissionMode.values, contains(ClaudePermissionMode.delegate));
    });
  });
}
