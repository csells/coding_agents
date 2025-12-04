import 'package:coding_agents/src/cli_adapters/gemini/gemini_cli_adapter.dart';
import 'package:coding_agents/src/cli_adapters/gemini/gemini_events.dart';
import 'package:coding_agents/src/cli_adapters/gemini/gemini_types.dart';
import 'package:test/test.dart';

void main() {
  group('GeminiClient', () {
    test('constructs with cwd', () {
      final client = GeminiCliAdapter(cwd: '/path/to/project');
      expect(client.cwd, '/path/to/project');
    });

    test('buildInitialArgs generates correct arguments for default config', () {
      final client = GeminiCliAdapter(cwd: '/test');
      final config = GeminiSessionConfig();

      final args = client.buildInitialArgs('test prompt', config);

      // Gemini CLI uses positional prompt and -o for output format
      expect(args, contains('test prompt'));
      expect(args, contains('-o'));
      expect(args, contains('stream-json'));
    });

    test('buildInitialArgs includes yolo flag', () {
      final client = GeminiCliAdapter(cwd: '/test');
      final config = GeminiSessionConfig(approvalMode: GeminiApprovalMode.yolo);

      final args = client.buildInitialArgs('test prompt', config);

      expect(args, contains('-y'));
    });

    test('buildInitialArgs includes auto-edit flag', () {
      final client = GeminiCliAdapter(cwd: '/test');
      final config = GeminiSessionConfig(
        approvalMode: GeminiApprovalMode.autoEdit,
      );

      final args = client.buildInitialArgs('test prompt', config);

      expect(args, contains('--auto-edit'));
    });

    test('buildInitialArgs includes sandbox flag', () {
      final client = GeminiCliAdapter(cwd: '/test');
      final config = GeminiSessionConfig(sandbox: true);

      final args = client.buildInitialArgs('test prompt', config);

      expect(args, contains('--sandbox'));
    });

    test('buildInitialArgs includes sandbox image', () {
      final client = GeminiCliAdapter(cwd: '/test');
      final config = GeminiSessionConfig(
        sandbox: true,
        sandboxImage: 'my-image:latest',
      );

      final args = client.buildInitialArgs('test prompt', config);

      expect(args, contains('--sandbox'));
      expect(args, contains('--sandbox-image'));
      expect(args, contains('my-image:latest'));
    });

    test('buildInitialArgs includes model when specified', () {
      final client = GeminiCliAdapter(cwd: '/test');
      final config = GeminiSessionConfig(model: 'gemini-2.0-flash-exp');

      final args = client.buildInitialArgs('test prompt', config);

      expect(args, contains('--model'));
      expect(args, contains('gemini-2.0-flash-exp'));
    });

    test('buildInitialArgs includes debug flag when enabled', () {
      final client = GeminiCliAdapter(cwd: '/test');
      final config = GeminiSessionConfig(debug: true);

      final args = client.buildInitialArgs('test prompt', config);

      expect(args, contains('--debug'));
    });

    test('buildResumeArgs generates correct arguments', () {
      final client = GeminiCliAdapter(cwd: '/test');
      final config = GeminiSessionConfig();

      final args = client.buildResumeArgs('sess-123-abc', 'continue', config);

      expect(args, contains('-p'));
      expect(args, contains('continue'));
      expect(args, contains('-o'));
      expect(args, contains('stream-json'));
      expect(args, contains('-r'));
      expect(args, contains('sess-123-abc'));
    });

    test('buildResumeArgs includes yolo flag for resumed session', () {
      final client = GeminiCliAdapter(cwd: '/test');
      final config = GeminiSessionConfig(approvalMode: GeminiApprovalMode.yolo);

      final args = client.buildResumeArgs('sess-456-def', 'continue', config);

      expect(args, contains('-y'));
      expect(args, contains('-r'));
      expect(args, contains('sess-456-def'));
    });

    test('buildResumeArgs includes sandbox for resumed session', () {
      final client = GeminiCliAdapter(cwd: '/test');
      final config = GeminiSessionConfig(
        sandbox: true,
        sandboxImage: 'image:v1',
      );

      final args = client.buildResumeArgs('sess-789-ghi', 'continue', config);

      expect(args, contains('--sandbox'));
      expect(args, contains('--sandbox-image'));
      expect(args, contains('image:v1'));
      expect(args, contains('-r'));
      expect(args, contains('sess-789-ghi'));
    });
  });

  group('GeminiClient event parsing', () {
    test('parseJsonLine parses valid JSONL', () {
      final client = GeminiCliAdapter(cwd: '/test');
      final line =
          '{"type":"init","session_id":"sess_123","model":"gemini-flash"}';

      final event = client.parseJsonLine(line, 'sess_123', 1);

      expect(event, isA<GeminiInitEvent>());
    });

    test('parseJsonLine returns null for empty line', () {
      final client = GeminiCliAdapter(cwd: '/test');

      expect(client.parseJsonLine('', '', 1), isNull);
      expect(client.parseJsonLine('   ', '', 1), isNull);
    });

    test('parseJsonLine returns null for non-JSON line', () {
      final client = GeminiCliAdapter(cwd: '/test');

      expect(client.parseJsonLine('not json', '', 1), isNull);
      expect(client.parseJsonLine('# comment', '', 1), isNull);
    });

    test('parseJsonLine throws on malformed JSON', () {
      final client = GeminiCliAdapter(cwd: '/test');

      expect(
        () => client.parseJsonLine('{malformed', '', 1),
        throwsA(isA<FormatException>()),
      );
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
