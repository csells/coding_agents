import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/claude_code/claude_config.dart';
import 'package:coding_agents/src/cli_adapters/claude_code/claude_types.dart';

void main() {
  group('ClaudeSessionConfig', () {
    test('constructs with defaults', () {
      final config = ClaudeSessionConfig();

      expect(config.permissionMode, ClaudePermissionMode.defaultMode);
      expect(config.permissionHandler, isNull);
      expect(config.model, isNull);
      expect(config.systemPrompt, isNull);
      expect(config.appendSystemPrompt, isNull);
      expect(config.maxTurns, isNull);
      expect(config.allowedTools, isNull);
      expect(config.disallowedTools, isNull);
    });

    test('constructs with custom permission mode', () {
      final config = ClaudeSessionConfig(
        permissionMode: ClaudePermissionMode.acceptEdits,
      );

      expect(config.permissionMode, ClaudePermissionMode.acceptEdits);
    });

    test('constructs with bypass permissions mode', () {
      final config = ClaudeSessionConfig(
        permissionMode: ClaudePermissionMode.bypassPermissions,
      );

      expect(config.permissionMode, ClaudePermissionMode.bypassPermissions);
    });

    test('constructs with delegate mode and handler', () {
      Future<ClaudeToolPermissionResponse> handler(
        ClaudeToolPermissionRequest req,
      ) async {
        return ClaudeToolPermissionResponse(
          behavior: ClaudePermissionBehavior.allow,
        );
      }

      final config = ClaudeSessionConfig(
        permissionMode: ClaudePermissionMode.delegate,
        permissionHandler: handler,
      );

      expect(config.permissionMode, ClaudePermissionMode.delegate);
      expect(config.permissionHandler, isNotNull);
    });

    test('throws when delegate mode used without handler', () {
      expect(
        () =>
            ClaudeSessionConfig(permissionMode: ClaudePermissionMode.delegate),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('constructs with model', () {
      final config = ClaudeSessionConfig(model: 'claude-sonnet-4-5-20250929');

      expect(config.model, 'claude-sonnet-4-5-20250929');
    });

    test('constructs with system prompt', () {
      final config = ClaudeSessionConfig(
        systemPrompt: 'You are a helpful assistant.',
      );

      expect(config.systemPrompt, 'You are a helpful assistant.');
    });

    test('constructs with append system prompt', () {
      final config = ClaudeSessionConfig(
        appendSystemPrompt: 'Always be concise.',
      );

      expect(config.appendSystemPrompt, 'Always be concise.');
    });

    test('constructs with maxTurns', () {
      final config = ClaudeSessionConfig(maxTurns: 10);

      expect(config.maxTurns, 10);
    });

    test('constructs with allowed tools', () {
      final config = ClaudeSessionConfig(
        allowedTools: ['Read', 'Edit', 'Bash(git log:*)'],
      );

      expect(config.allowedTools, hasLength(3));
      expect(config.allowedTools, contains('Read'));
      expect(config.allowedTools, contains('Bash(git log:*)'));
    });

    test('constructs with disallowed tools', () {
      final config = ClaudeSessionConfig(disallowedTools: ['Bash', 'Write']);

      expect(config.disallowedTools, hasLength(2));
      expect(config.disallowedTools, contains('Bash'));
    });

    test('constructs with all options', () {
      Future<ClaudeToolPermissionResponse> handler(
        ClaudeToolPermissionRequest req,
      ) async {
        return ClaudeToolPermissionResponse(
          behavior: ClaudePermissionBehavior.allow,
        );
      }

      final config = ClaudeSessionConfig(
        permissionMode: ClaudePermissionMode.delegate,
        permissionHandler: handler,
        model: 'claude-opus-4-5-20251101',
        systemPrompt: 'Custom prompt',
        appendSystemPrompt: 'Extra instructions',
        maxTurns: 5,
        allowedTools: ['Read'],
        disallowedTools: ['Write'],
      );

      expect(config.permissionMode, ClaudePermissionMode.delegate);
      expect(config.permissionHandler, isNotNull);
      expect(config.model, 'claude-opus-4-5-20251101');
      expect(config.systemPrompt, 'Custom prompt');
      expect(config.appendSystemPrompt, 'Extra instructions');
      expect(config.maxTurns, 5);
      expect(config.allowedTools, ['Read']);
      expect(config.disallowedTools, ['Write']);
    });
  });
}
