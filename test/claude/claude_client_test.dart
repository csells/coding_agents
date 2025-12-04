import 'dart:convert';

import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/claude/claude_client.dart';
import 'package:coding_agents/src/cli_adapters/claude/claude_config.dart';
import 'package:coding_agents/src/cli_adapters/claude/claude_events.dart';
import 'package:coding_agents/src/cli_adapters/claude/claude_types.dart';

void main() {
  group('ClaudeClient', () {
    test('constructs with cwd', () {
      final client = ClaudeClient(cwd: '/path/to/project');
      expect(client.cwd, '/path/to/project');
    });

    test('buildArgs generates correct arguments for default config', () {
      final client = ClaudeClient(cwd: '/test');
      final config = ClaudeSessionConfig();

      final args = client.buildArgs(config, 'test prompt', null);

      expect(args, contains('-p'));
      expect(args, contains('test prompt'));
      expect(args, contains('--output-format'));
      expect(args, contains('stream-json'));
    });

    test('buildArgs includes resume flag when sessionId provided', () {
      final client = ClaudeClient(cwd: '/test');
      final config = ClaudeSessionConfig();

      final args = client.buildArgs(config, 'continue', 'sess_abc123');

      expect(args, contains('--resume'));
      expect(args, contains('sess_abc123'));
    });

    test('buildArgs includes acceptEdits permission mode', () {
      final client = ClaudeClient(cwd: '/test');
      final config = ClaudeSessionConfig(
        permissionMode: ClaudePermissionMode.acceptEdits,
      );

      final args = client.buildArgs(config, 'test', null);

      expect(args, contains('--permission-mode'));
      expect(args, contains('acceptEdits'));
    });

    test('buildArgs includes bypassPermissions mode', () {
      final client = ClaudeClient(cwd: '/test');
      final config = ClaudeSessionConfig(
        permissionMode: ClaudePermissionMode.bypassPermissions,
      );

      final args = client.buildArgs(config, 'test', null);

      expect(args, contains('--dangerously-skip-permissions'));
    });

    test('buildArgs includes delegate permission mode with MCP tool', () {
      final client = ClaudeClient(cwd: '/test');
      final config = ClaudeSessionConfig(
        permissionMode: ClaudePermissionMode.delegate,
        permissionHandler: (_) async => ClaudeToolPermissionResponse(
          behavior: ClaudePermissionBehavior.allow,
        ),
      );

      final args = client.buildArgs(config, 'test', null);

      expect(args, contains('--permission-prompt-tool'));
      expect(args.any((a) => a.contains('mcp__')), isTrue);
    });

    test('buildArgs includes model when specified', () {
      final client = ClaudeClient(cwd: '/test');
      final config = ClaudeSessionConfig(
        model: 'claude-opus-4-5-20251101',
      );

      final args = client.buildArgs(config, 'test', null);

      expect(args, contains('--model'));
      expect(args, contains('claude-opus-4-5-20251101'));
    });

    test('buildArgs includes system prompt when specified', () {
      final client = ClaudeClient(cwd: '/test');
      final config = ClaudeSessionConfig(
        systemPrompt: 'You are a code reviewer.',
      );

      final args = client.buildArgs(config, 'test', null);

      expect(args, contains('--system-prompt'));
      expect(args, contains('You are a code reviewer.'));
    });

    test('buildArgs includes append system prompt when specified', () {
      final client = ClaudeClient(cwd: '/test');
      final config = ClaudeSessionConfig(
        appendSystemPrompt: 'Be concise.',
      );

      final args = client.buildArgs(config, 'test', null);

      expect(args, contains('--append-system-prompt'));
      expect(args, contains('Be concise.'));
    });

    test('buildArgs includes maxTurns when specified', () {
      final client = ClaudeClient(cwd: '/test');
      final config = ClaudeSessionConfig(maxTurns: 5);

      final args = client.buildArgs(config, 'test', null);

      expect(args, contains('--max-turns'));
      expect(args, contains('5'));
    });

    test('buildArgs includes allowed tools when specified', () {
      final client = ClaudeClient(cwd: '/test');
      final config = ClaudeSessionConfig(
        allowedTools: ['Read', 'Edit'],
      );

      final args = client.buildArgs(config, 'test', null);

      expect(args, contains('--allowedTools'));
      expect(args, contains('Read'));
      expect(args, contains('Edit'));
    });

    test('buildArgs includes disallowed tools when specified', () {
      final client = ClaudeClient(cwd: '/test');
      final config = ClaudeSessionConfig(
        disallowedTools: ['Bash', 'Write'],
      );

      final args = client.buildArgs(config, 'test', null);

      expect(args, contains('--disallowedTools'));
      expect(args, contains('Bash'));
      expect(args, contains('Write'));
    });
  });

  group('ClaudeClient event parsing', () {
    test('parseJsonLine parses valid JSONL', () {
      final client = ClaudeClient(cwd: '/test');
      final line = '{"type":"init","session_id":"sess_123"}';

      final event = client.parseJsonLine(line, 1);

      expect(event, isA<ClaudeInitEvent>());
    });

    test('parseJsonLine returns null for empty line', () {
      final client = ClaudeClient(cwd: '/test');

      expect(client.parseJsonLine('', 1), isNull);
      expect(client.parseJsonLine('   ', 1), isNull);
    });

    test('parseJsonLine returns null for non-JSON line', () {
      final client = ClaudeClient(cwd: '/test');

      expect(client.parseJsonLine('not json', 1), isNull);
      expect(client.parseJsonLine('# comment', 1), isNull);
    });

    test('parseJsonLine throws on malformed JSON', () {
      final client = ClaudeClient(cwd: '/test');

      expect(
        () => client.parseJsonLine('{malformed', 1),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ClaudeSession', () {
    test('formats user message correctly for send', () {
      final message = ClaudeClient.formatUserMessage('Hello Claude');

      final parsed = jsonDecode(message);
      expect(parsed['type'], 'user');
      expect(parsed['message']['role'], 'user');
      expect(parsed['message']['content'], hasLength(1));
      expect(parsed['message']['content'][0]['type'], 'text');
      expect(parsed['message']['content'][0]['text'], 'Hello Claude');
    });
  });

  group('ClaudeProcessException', () {
    test('has descriptive toString', () {
      final exception = ClaudeProcessException('Process exited with code 1');

      expect(exception.toString(), contains('ClaudeProcessException'));
      expect(exception.toString(), contains('Process exited with code 1'));
    });

    test('stores message', () {
      final exception = ClaudeProcessException('test message');
      expect(exception.message, 'test message');
    });
  });
}
