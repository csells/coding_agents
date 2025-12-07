import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/gemini/gemini_types.dart';

void main() {
  group('GeminiSessionConfig', () {
    test('constructs with defaults', () {
      final config = GeminiSessionConfig();

      expect(config.approvalMode, GeminiApprovalMode.defaultMode);
      expect(config.sandbox, isFalse);
      expect(config.sandboxImage, isNull);
      expect(config.model, isNull);
      expect(config.debug, isFalse);
    });

    test('constructs with autoEdit approval mode', () {
      final config = GeminiSessionConfig(
        approvalMode: GeminiApprovalMode.autoEdit,
      );

      expect(config.approvalMode, GeminiApprovalMode.autoEdit);
    });

    test('constructs with yolo approval mode', () {
      final config = GeminiSessionConfig(approvalMode: GeminiApprovalMode.yolo);

      expect(config.approvalMode, GeminiApprovalMode.yolo);
    });

    test('constructs with sandbox enabled', () {
      final config = GeminiSessionConfig(sandbox: true);

      expect(config.sandbox, isTrue);
    });

    test('constructs with sandbox image', () {
      final config = GeminiSessionConfig(
        sandbox: true,
        sandboxImage: 'my-custom-sandbox:latest',
      );

      expect(config.sandbox, isTrue);
      expect(config.sandboxImage, 'my-custom-sandbox:latest');
    });

    test('constructs with model', () {
      final config = GeminiSessionConfig(model: 'gemini-2.0-flash-exp');

      expect(config.model, 'gemini-2.0-flash-exp');
    });

    test('constructs with debug enabled', () {
      final config = GeminiSessionConfig(debug: true);

      expect(config.debug, isTrue);
    });

    test('constructs with all options', () {
      final config = GeminiSessionConfig(
        approvalMode: GeminiApprovalMode.yolo,
        sandbox: true,
        sandboxImage: 'custom-image:v1',
        model: 'gemini-pro',
        debug: true,
      );

      expect(config.approvalMode, GeminiApprovalMode.yolo);
      expect(config.sandbox, isTrue);
      expect(config.sandboxImage, 'custom-image:v1');
      expect(config.model, 'gemini-pro');
      expect(config.debug, isTrue);
    });
  });
}
