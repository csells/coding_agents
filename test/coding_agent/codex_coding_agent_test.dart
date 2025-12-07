import 'package:coding_agents/src/coding_agent/coding_agents.dart';
import 'package:test/test.dart';

void main() {
  group('CodexCodingAgent', () {
    test('can be instantiated with default config', () {
      final agent = CodexCodingAgent();

      expect(agent.approvalPolicy, equals(CodexApprovalPolicy.onRequest));
      expect(agent.sandboxMode, equals(CodexSandboxMode.workspaceWrite));
      expect(agent.fullAuto, isFalse);
      expect(agent.dangerouslyBypassAll, isFalse);
      expect(agent.model, isNull);
      expect(agent.enableWebSearch, isFalse);
      expect(agent.environment, isNull);
      expect(agent.configOverrides, isNull);
    });

    test('can be instantiated with custom config', () {
      final agent = CodexCodingAgent(
        approvalPolicy: CodexApprovalPolicy.never,
        sandboxMode: CodexSandboxMode.dangerFullAccess,
        fullAuto: true,
        dangerouslyBypassAll: true,
        model: 'o3',
        enableWebSearch: true,
        environment: {'API_KEY': 'secret'},
        configOverrides: ['key=value'],
      );

      expect(agent.approvalPolicy, equals(CodexApprovalPolicy.never));
      expect(agent.sandboxMode, equals(CodexSandboxMode.dangerFullAccess));
      expect(agent.fullAuto, isTrue);
      expect(agent.dangerouslyBypassAll, isTrue);
      expect(agent.model, equals('o3'));
      expect(agent.enableWebSearch, isTrue);
      expect(agent.environment, equals({'API_KEY': 'secret'}));
      expect(agent.configOverrides, equals(['key=value']));
    });

    test('implements CodingAgent interface', () {
      final agent = CodexCodingAgent();

      expect(agent, isA<CodingAgent>());
    });
  });

  group('CodexApprovalPolicy', () {
    test('has all expected values', () {
      expect(CodexApprovalPolicy.values, hasLength(4));
      expect(CodexApprovalPolicy.values, contains(CodexApprovalPolicy.onRequest));
      expect(CodexApprovalPolicy.values, contains(CodexApprovalPolicy.untrusted));
      expect(CodexApprovalPolicy.values, contains(CodexApprovalPolicy.onFailure));
      expect(CodexApprovalPolicy.values, contains(CodexApprovalPolicy.never));
    });
  });

  group('CodexSandboxMode', () {
    test('has all expected values', () {
      expect(CodexSandboxMode.values, hasLength(3));
      expect(CodexSandboxMode.values, contains(CodexSandboxMode.readOnly));
      expect(CodexSandboxMode.values, contains(CodexSandboxMode.workspaceWrite));
      expect(CodexSandboxMode.values, contains(CodexSandboxMode.dangerFullAccess));
    });
  });
}
