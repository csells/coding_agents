import 'package:coding_agents/src/coding_agent/coding_agents.dart';
import 'package:test/test.dart';

void main() {
  group('GeminiCodingAgent', () {
    test('can be instantiated with default config', () {
      final agent = GeminiCodingAgent();

      expect(agent.approvalMode, equals(GeminiApprovalMode.defaultMode));
      expect(agent.sandbox, isFalse);
      expect(agent.sandboxImage, isNull);
      expect(agent.model, isNull);
      expect(agent.debug, isFalse);
    });

    test('can be instantiated with custom config', () {
      final agent = GeminiCodingAgent(
        approvalMode: GeminiApprovalMode.yolo,
        sandbox: true,
        sandboxImage: 'custom-image:latest',
        model: 'gemini-2.0-flash-exp',
        debug: true,
      );

      expect(agent.approvalMode, equals(GeminiApprovalMode.yolo));
      expect(agent.sandbox, isTrue);
      expect(agent.sandboxImage, equals('custom-image:latest'));
      expect(agent.model, equals('gemini-2.0-flash-exp'));
      expect(agent.debug, isTrue);
    });

    test('implements CodingAgent interface', () {
      final agent = GeminiCodingAgent();

      expect(agent, isA<CodingAgent>());
    });
  });

  group('GeminiApprovalMode', () {
    test('has all expected values', () {
      expect(GeminiApprovalMode.values, hasLength(3));
      expect(GeminiApprovalMode.values, contains(GeminiApprovalMode.defaultMode));
      expect(GeminiApprovalMode.values, contains(GeminiApprovalMode.autoEdit));
      expect(GeminiApprovalMode.values, contains(GeminiApprovalMode.yolo));
    });
  });
}
