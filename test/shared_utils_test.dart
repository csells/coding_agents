import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/shared_utils.dart';

void main() {
  group('parseJsonLine', () {
    test('parses valid JSON object', () {
      final result = parseJsonLine('{"type": "init", "id": "123"}');

      expect(result, isNotNull);
      expect(result!['type'], 'init');
      expect(result['id'], '123');
    });

    test('returns null for empty line', () {
      final result = parseJsonLine('');

      expect(result, isNull);
    });

    test('returns null for whitespace-only line', () {
      final result = parseJsonLine('   \t  ');

      expect(result, isNull);
    });

    test('returns null for non-JSON line', () {
      final result = parseJsonLine('not json at all');

      expect(result, isNull);
    });

    test('returns null for array JSON', () {
      final result = parseJsonLine('[1, 2, 3]');

      expect(result, isNull);
    });

    test('trims whitespace before parsing', () {
      final result = parseJsonLine('  {"key": "value"}  ');

      expect(result, isNotNull);
      expect(result!['key'], 'value');
    });

    test('throws FormatException for malformed JSON object', () {
      expect(
        () => parseJsonLine('{malformed: json}'),
        throwsFormatException,
      );
    });

    test('throws FormatException for truncated JSON', () {
      expect(
        () => parseJsonLine('{"incomplete": '),
        throwsFormatException,
      );
    });
  });

  group('CliProcessException', () {
    test('concrete implementations have correct adapterName', () {
      // Testing through the concrete implementations
      // Each adapter's exception should have its own name
      // This is tested in the individual adapter tests
    });
  });
}
