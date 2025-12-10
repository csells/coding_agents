import 'package:coding_agents/src/cli_adapters/codex/codex_cli_adapter.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_config.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_types.dart';
import 'package:test/test.dart';

void main() {
  group('CodexCliAdapter', () {
    test('buildAppServerArgs generates correct arguments for default config',
        () {
      final client = CodexCliAdapter();
      final config = CodexSessionConfig();

      final args = client.buildAppServerArgs(config);

      expect(args, contains('app-server'));
      expect(args, contains('-c'));
      // NOTE: No quotes around values - Process.start doesn't use shell processing
      expect(args.any((a) => a.contains('approval_policy=on-request')), isTrue);
      expect(
        args.any((a) => a.contains('sandbox_mode=workspace-write')),
        isTrue,
      );
    });

    test('buildAppServerArgs includes fullAuto config overrides', () {
      final client = CodexCliAdapter();
      final config = CodexSessionConfig(fullAuto: true);

      final args = client.buildAppServerArgs(config);

      expect(args.any((a) => a.contains('approval_policy=on-failure')), isTrue);
      expect(
        args.any((a) => a.contains('sandbox_mode=workspace-write')),
        isTrue,
      );
    });

    test('buildAppServerArgs includes model when specified', () {
      final client = CodexCliAdapter();
      final config = CodexSessionConfig(model: 'o3');

      final args = client.buildAppServerArgs(config);

      expect(args, contains('-c'));
      expect(args.any((a) => a.contains('model=o3')), isTrue);
    });

    test('buildAppServerArgs includes untrusted approval policy', () {
      final client = CodexCliAdapter();
      final config = CodexSessionConfig(
        approvalPolicy: CodexApprovalPolicy.untrusted,
      );

      final args = client.buildAppServerArgs(config);

      expect(args, contains('-c'));
      expect(args.any((a) => a.contains('approval_policy=untrusted')), isTrue);
    });

    test('buildAppServerArgs includes readOnly sandbox mode', () {
      final client = CodexCliAdapter();
      final config = CodexSessionConfig(sandboxMode: CodexSandboxMode.readOnly);

      final args = client.buildAppServerArgs(config);

      expect(args, contains('-c'));
      expect(args.any((a) => a.contains('sandbox_mode=read-only')), isTrue);
    });

    test('buildAppServerArgs includes config overrides', () {
      final client = CodexCliAdapter();
      final config = CodexSessionConfig(
        configOverrides: ['model_reasoning_effort="high"'],
      );

      final args = client.buildAppServerArgs(config);

      expect(args, contains('-c'));
      expect(args, contains('model_reasoning_effort="high"'));
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
