import 'package:coding_agents/src/cli_adapters/codex/codex_cli_adapter.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_config.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_events.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_types.dart';
import 'package:test/test.dart';

void main() {
  group('CodexClient', () {
    test('constructs with cwd', () {
      final client = CodexCliAdapter(cwd: '/path/to/project');
      expect(client.cwd, '/path/to/project');
    });

    test('buildInitialArgs generates correct arguments for default config', () {
      final client = CodexCliAdapter(cwd: '/test');
      final config = CodexSessionConfig();

      final args = client.buildInitialArgs('test prompt', config);

      expect(args, contains('exec'));
      expect(args, contains('--json'));
      expect(args, contains('test prompt'));
      expect(args, contains('-a'));
      expect(args.any((a) => a.contains('on-request')), isTrue);
      expect(args, contains('-s'));
      expect(args.any((a) => a.contains('workspace-write')), isTrue);
    });

    test('buildInitialArgs includes fullAuto flag', () {
      final client = CodexCliAdapter(cwd: '/test');
      final config = CodexSessionConfig(fullAuto: true);

      final args = client.buildInitialArgs('test prompt', config);

      expect(args, contains('--full-auto'));
      // Should not include -a or -s when fullAuto is true
      expect(args.where((a) => a == '-a'), isEmpty);
      expect(args.where((a) => a == '-s'), isEmpty);
    });

    test('buildInitialArgs includes dangerouslyBypassAll flag', () {
      final client = CodexCliAdapter(cwd: '/test');
      final config = CodexSessionConfig(dangerouslyBypassAll: true);

      final args = client.buildInitialArgs('test prompt', config);

      expect(args, contains('--dangerously-bypass-approvals-and-sandbox'));
    });

    test('buildInitialArgs includes model when specified', () {
      final client = CodexCliAdapter(cwd: '/test');
      final config = CodexSessionConfig(model: 'o3');

      final args = client.buildInitialArgs('test prompt', config);

      expect(args, contains('-m'));
      expect(args, contains('o3'));
    });

    test('buildInitialArgs includes search flag when enabled', () {
      final client = CodexCliAdapter(cwd: '/test');
      final config = CodexSessionConfig(enableWebSearch: true);

      final args = client.buildInitialArgs('test prompt', config);

      expect(args, contains('--search'));
    });

    test('buildInitialArgs includes untrusted approval policy', () {
      final client = CodexCliAdapter(cwd: '/test');
      final config = CodexSessionConfig(
        approvalPolicy: CodexApprovalPolicy.untrusted,
      );

      final args = client.buildInitialArgs('test prompt', config);

      expect(args, contains('-a'));
      expect(args.any((a) => a.contains('untrusted')), isTrue);
    });

    test('buildInitialArgs includes readOnly sandbox mode', () {
      final client = CodexCliAdapter(cwd: '/test');
      final config = CodexSessionConfig(sandboxMode: CodexSandboxMode.readOnly);

      final args = client.buildInitialArgs('test prompt', config);

      expect(args, contains('-s'));
      expect(args.any((a) => a.contains('read-only')), isTrue);
    });

    test('buildResumeArgs generates correct arguments', () {
      final client = CodexCliAdapter(cwd: '/test');
      final config = CodexSessionConfig();

      final args = client.buildResumeArgs(
        'continue please',
        'thread_123',
        config,
      );

      expect(args, contains('exec'));
      expect(args, contains('--json'));
      expect(args, contains('resume'));
      expect(args, contains('thread_123'));
      expect(args, contains('continue please'));
    });

    test('buildResumeArgs includes fullAuto for resumed session', () {
      final client = CodexCliAdapter(cwd: '/test');
      final config = CodexSessionConfig(fullAuto: true);

      final args = client.buildResumeArgs('continue', 'thread_123', config);

      expect(args, contains('--full-auto'));
      expect(args, contains('resume'));
      expect(args, contains('thread_123'));
    });
  });

  group('CodexClient event parsing', () {
    test('parseJsonLine parses valid JSONL', () {
      final client = CodexCliAdapter(cwd: '/test');
      final line = '{"type":"thread.started","thread_id":"thread_123"}';

      final event = client.parseJsonLine(line, 'thread_123', 1);

      expect(event, isA<CodexThreadStartedEvent>());
    });

    test('parseJsonLine returns null for empty line', () {
      final client = CodexCliAdapter(cwd: '/test');

      expect(client.parseJsonLine('', '', 1), isNull);
      expect(client.parseJsonLine('   ', '', 1), isNull);
    });

    test('parseJsonLine returns null for non-JSON line', () {
      final client = CodexCliAdapter(cwd: '/test');

      expect(client.parseJsonLine('not json', '', 1), isNull);
      expect(client.parseJsonLine('# comment', '', 1), isNull);
    });

    test('parseJsonLine throws on malformed JSON', () {
      final client = CodexCliAdapter(cwd: '/test');

      expect(
        () => client.parseJsonLine('{malformed', '', 1),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('CodexClient formatEnumArg', () {
    test('converts camelCase to kebab-case', () {
      final client = CodexCliAdapter(cwd: '/test');

      expect(client.formatEnumArg('onRequest'), 'on-request');
      expect(client.formatEnumArg('onFailure'), 'on-failure');
      expect(client.formatEnumArg('workspaceWrite'), 'workspace-write');
      expect(client.formatEnumArg('dangerFullAccess'), 'danger-full-access');
      expect(client.formatEnumArg('readOnly'), 'read-only');
    });

    test('handles single word', () {
      final client = CodexCliAdapter(cwd: '/test');

      expect(client.formatEnumArg('never'), 'never');
      expect(client.formatEnumArg('untrusted'), 'untrusted');
    });
  });

  group('CodexProcessException', () {
    test('has descriptive toString', () {
      final exception = CodexProcessException('Process exited with code 1');

      expect(exception.toString(), contains('CodexProcessException'));
      expect(exception.toString(), contains('Process exited with code 1'));
    });

    test('stores message', () {
      final exception = CodexProcessException('test message');
      expect(exception.message, 'test message');
    });
  });
}
