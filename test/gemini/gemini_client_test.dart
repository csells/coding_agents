import 'package:coding_agents/src/cli_adapters/gemini/gemini_session.dart';
import 'package:coding_agents/src/cli_adapters/gemini/gemini_types.dart';
import 'package:test/test.dart';

void main() {
  group('GeminiSessionConfig', () {
    test('default config has correct defaults', () {
      final config = GeminiSessionConfig();

      expect(config.approvalMode, GeminiApprovalMode.defaultMode);
      expect(config.sandbox, isFalse);
      expect(config.sandboxImage, isNull);
      expect(config.model, isNull);
      expect(config.debug, isFalse);
      expect(config.extraArgs, isNull);
    });

    test('config with yolo mode', () {
      final config = GeminiSessionConfig(approvalMode: GeminiApprovalMode.yolo);

      expect(config.approvalMode, GeminiApprovalMode.yolo);
    });

    test('config with auto-edit mode', () {
      final config = GeminiSessionConfig(
        approvalMode: GeminiApprovalMode.autoEdit,
      );

      expect(config.approvalMode, GeminiApprovalMode.autoEdit);
    });

    test('config with sandbox settings', () {
      final config = GeminiSessionConfig(
        sandbox: true,
        sandboxImage: 'my-image:latest',
      );

      expect(config.sandbox, isTrue);
      expect(config.sandboxImage, 'my-image:latest');
    });

    test('config with model specified', () {
      final config = GeminiSessionConfig(model: 'gemini-2.0-flash-exp');

      expect(config.model, 'gemini-2.0-flash-exp');
    });

    test('config with debug enabled', () {
      final config = GeminiSessionConfig(debug: true);

      expect(config.debug, isTrue);
    });

    test('config with extra args', () {
      final config = GeminiSessionConfig(extraArgs: ['--verbose', '--trace']);

      expect(config.extraArgs, ['--verbose', '--trace']);
    });
  });

  group('GeminiProcessException', () {
    test('has descriptive toString', () {
      final exception = GeminiProcessException('Process exited with code 1');

      expect(exception.toString(), contains('GeminiProcessException'));
      expect(exception.toString(), contains('Process exited with code 1'));
    });

    test('stores message', () {
      final exception = GeminiProcessException('test message');
      expect(exception.message, 'test message');
    });
  });
}
