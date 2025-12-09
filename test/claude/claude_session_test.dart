import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/claude_code/claude_session.dart';

void main() {
  group('ClaudeSession', () {
    group('formatUserMessage', () {
      test('formats simple text message correctly', () {
        final result = ClaudeSession.formatUserMessage('Hello, Claude!');

        expect(result, contains('"type":"user"'));
        expect(result, contains('"role":"user"'));
        expect(result, contains('"text":"Hello, Claude!"'));
      });

      test('formats message with special characters', () {
        final result = ClaudeSession.formatUserMessage('Line1\nLine2\tTabbed');

        // JSON should escape special characters
        expect(result, contains(r'\n'));
        expect(result, contains(r'\t'));
      });

      test('formats message with unicode', () {
        final result = ClaudeSession.formatUserMessage('Hello 世界 🌍');

        expect(result, contains('Hello 世界 🌍'));
      });

      test('formats message with quotes', () {
        final result = ClaudeSession.formatUserMessage('Say "hello"');

        // JSON should escape quotes
        expect(result, contains(r'\"hello\"'));
      });

      test('formats empty message', () {
        final result = ClaudeSession.formatUserMessage('');

        expect(result, contains('"text":""'));
      });

      test('produces valid JSON structure', () {
        final result = ClaudeSession.formatUserMessage('test');

        // Verify JSON structure
        expect(result, startsWith('{'));
        expect(result, endsWith('}'));
        expect(
          result,
          contains('"content":[{"type":"text","text":"test"}]'),
        );
      });
    });
  });
}
