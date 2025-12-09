import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/gemini/gemini_session.dart';
import 'package:coding_agents/src/cli_adapters/gemini/gemini_types.dart';
import 'package:coding_agents/src/cli_adapters/shared_utils.dart';

void main() {
  group('GeminiProcessException', () {
    test('creates with message', () {
      final exception = GeminiProcessException('Process failed');

      expect(exception.message, 'Process failed');
      expect(exception.toString(), 'GeminiProcessException: Process failed');
    });

    test('creates with empty message', () {
      final exception = GeminiProcessException('');

      expect(exception.message, '');
      expect(exception.toString(), 'GeminiProcessException: ');
    });

    test('creates with multiline message', () {
      final exception = GeminiProcessException('Line 1\nLine 2\nLine 3');

      expect(exception.message, 'Line 1\nLine 2\nLine 3');
    });

    test('extends CliProcessException', () {
      final exception = GeminiProcessException('test');

      expect(exception, isA<CliProcessException>());
      expect(exception.adapterName, 'GeminiProcessException');
    });
  });

  group('GeminiSession.create', () {
    test('creates session with default config', () {
      final config = GeminiSessionConfig();
      final session = GeminiSession.create(
        config: config,
        projectDirectory: '/test/project',
        turnId: 0,
      );

      expect(session.sessionId, isNull);
      expect(session.currentTurnId, 0);
    });

    test('creates session with custom turn ID', () {
      final config = GeminiSessionConfig();
      final session = GeminiSession.create(
        config: config,
        projectDirectory: '/test/project',
        turnId: 5,
      );

      expect(session.currentTurnId, 5);
    });
  });

  group('GeminiSession.createForResume', () {
    test('creates session with existing session ID', () {
      final config = GeminiSessionConfig();
      final session = GeminiSession.createForResume(
        sessionId: 'existing-session-123',
        config: config,
        projectDirectory: '/test/project',
        turnId: 3,
      );

      expect(session.sessionId, 'existing-session-123');
      expect(session.currentTurnId, 3);
    });
  });

  group('GeminiSessionConfig', () {
    test('default config values', () {
      final config = GeminiSessionConfig();

      expect(config.approvalMode, GeminiApprovalMode.defaultMode);
      expect(config.sandbox, false);
      expect(config.sandboxImage, isNull);
      expect(config.model, isNull);
      expect(config.debug, false);
      expect(config.extraArgs, isNull);
    });

    test('creates with all custom values', () {
      final config = GeminiSessionConfig(
        approvalMode: GeminiApprovalMode.yolo,
        sandbox: true,
        sandboxImage: 'custom-image:latest',
        model: 'gemini-2.0-flash-exp',
        debug: true,
        extraArgs: ['--verbose'],
      );

      expect(config.approvalMode, GeminiApprovalMode.yolo);
      expect(config.sandbox, true);
      expect(config.sandboxImage, 'custom-image:latest');
      expect(config.model, 'gemini-2.0-flash-exp');
      expect(config.debug, true);
      expect(config.extraArgs, ['--verbose']);
    });

    test('serializes to JSON and back', () {
      final original = GeminiSessionConfig(
        approvalMode: GeminiApprovalMode.autoEdit,
        sandbox: true,
        model: 'gemini-pro',
        debug: true,
      );

      final json = original.toJson();
      final restored = GeminiSessionConfig.fromJson(json);

      expect(restored.approvalMode, original.approvalMode);
      expect(restored.sandbox, original.sandbox);
      expect(restored.model, original.model);
      expect(restored.debug, original.debug);
    });
  });

  group('GeminiApprovalMode', () {
    test('all modes exist', () {
      expect(GeminiApprovalMode.values, hasLength(3));
      expect(GeminiApprovalMode.values, contains(GeminiApprovalMode.defaultMode));
      expect(GeminiApprovalMode.values, contains(GeminiApprovalMode.autoEdit));
      expect(GeminiApprovalMode.values, contains(GeminiApprovalMode.yolo));
    });
  });
}
