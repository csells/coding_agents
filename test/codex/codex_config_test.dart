import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_config.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_types.dart';

void main() {
  group('CodexSessionConfig', () {
    test('constructs with defaults', () {
      final config = CodexSessionConfig();

      expect(config.approvalPolicy, CodexApprovalPolicy.onRequest);
      expect(config.sandboxMode, CodexSandboxMode.workspaceWrite);
      expect(config.fullAuto, isFalse);
      expect(config.dangerouslyBypassAll, isFalse);
      expect(config.model, isNull);
      expect(config.enableWebSearch, isFalse);
      expect(config.environment, isNull);
    });

    test('constructs with untrusted approval policy', () {
      final config = CodexSessionConfig(
        approvalPolicy: CodexApprovalPolicy.untrusted,
      );

      expect(config.approvalPolicy, CodexApprovalPolicy.untrusted);
    });

    test('constructs with onFailure approval policy', () {
      final config = CodexSessionConfig(
        approvalPolicy: CodexApprovalPolicy.onFailure,
      );

      expect(config.approvalPolicy, CodexApprovalPolicy.onFailure);
    });

    test('constructs with never approval policy', () {
      final config = CodexSessionConfig(
        approvalPolicy: CodexApprovalPolicy.never,
      );

      expect(config.approvalPolicy, CodexApprovalPolicy.never);
    });

    test('constructs with readOnly sandbox mode', () {
      final config = CodexSessionConfig(
        sandboxMode: CodexSandboxMode.readOnly,
      );

      expect(config.sandboxMode, CodexSandboxMode.readOnly);
    });

    test('constructs with dangerFullAccess sandbox mode', () {
      final config = CodexSessionConfig(
        sandboxMode: CodexSandboxMode.dangerFullAccess,
      );

      expect(config.sandboxMode, CodexSandboxMode.dangerFullAccess);
    });

    test('constructs with fullAuto mode', () {
      final config = CodexSessionConfig(fullAuto: true);

      expect(config.fullAuto, isTrue);
    });

    test('constructs with dangerouslyBypassAll', () {
      final config = CodexSessionConfig(dangerouslyBypassAll: true);

      expect(config.dangerouslyBypassAll, isTrue);
    });

    test('constructs with model', () {
      final config = CodexSessionConfig(model: 'o3');

      expect(config.model, 'o3');
    });

    test('constructs with web search enabled', () {
      final config = CodexSessionConfig(enableWebSearch: true);

      expect(config.enableWebSearch, isTrue);
    });

    test('constructs with environment variables', () {
      final config = CodexSessionConfig(
        environment: {
          'API_KEY': 'secret',
          'DEBUG': 'true',
        },
      );

      expect(config.environment, hasLength(2));
      expect(config.environment!['API_KEY'], 'secret');
      expect(config.environment!['DEBUG'], 'true');
    });

    test('constructs with all options', () {
      final config = CodexSessionConfig(
        approvalPolicy: CodexApprovalPolicy.untrusted,
        sandboxMode: CodexSandboxMode.readOnly,
        fullAuto: false,
        dangerouslyBypassAll: false,
        model: 'o3-mini',
        enableWebSearch: true,
        environment: {'KEY': 'value'},
      );

      expect(config.approvalPolicy, CodexApprovalPolicy.untrusted);
      expect(config.sandboxMode, CodexSandboxMode.readOnly);
      expect(config.fullAuto, isFalse);
      expect(config.dangerouslyBypassAll, isFalse);
      expect(config.model, 'o3-mini');
      expect(config.enableWebSearch, isTrue);
      expect(config.environment, {'KEY': 'value'});
    });
  });
}
