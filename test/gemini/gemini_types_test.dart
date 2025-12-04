import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/gemini/gemini_types.dart';

void main() {
  group('GeminiApprovalMode', () {
    test('has all expected values', () {
      expect(GeminiApprovalMode.values, hasLength(3));
      expect(GeminiApprovalMode.values, contains(GeminiApprovalMode.defaultMode));
      expect(GeminiApprovalMode.values, contains(GeminiApprovalMode.autoEdit));
      expect(GeminiApprovalMode.values, contains(GeminiApprovalMode.yolo));
    });
  });

  group('GeminiSessionInfo', () {
    test('constructs with required fields', () {
      final info = GeminiSessionInfo(
        sessionId: 'sess_123',
        projectHash: 'abc123',
        startTime: DateTime(2025, 1, 1),
        lastUpdated: DateTime(2025, 1, 2),
        messageCount: 10,
      );

      expect(info.sessionId, 'sess_123');
      expect(info.projectHash, 'abc123');
      expect(info.startTime, DateTime(2025, 1, 1));
      expect(info.lastUpdated, DateTime(2025, 1, 2));
      expect(info.messageCount, 10);
    });

    test('serializes to JSON', () {
      final info = GeminiSessionInfo(
        sessionId: 'sess_456',
        projectHash: 'def456',
        startTime: DateTime.utc(2025, 1, 1),
        lastUpdated: DateTime.utc(2025, 1, 2),
        messageCount: 5,
      );

      final json = info.toJson();
      expect(json['sessionId'], 'sess_456');
      expect(json['projectHash'], 'def456');
      expect(json['messageCount'], 5);
    });

    test('deserializes from JSON', () {
      final json = {
        'sessionId': 'sess_789',
        'projectHash': 'ghi789',
        'startTime': '2025-01-01T00:00:00.000Z',
        'lastUpdated': '2025-01-02T00:00:00.000Z',
        'messageCount': 15,
      };

      final info = GeminiSessionInfo.fromJson(json);
      expect(info.sessionId, 'sess_789');
      expect(info.projectHash, 'ghi789');
      expect(info.messageCount, 15);
    });
  });

  group('GeminiStats', () {
    test('constructs with required fields', () {
      final stats = GeminiStats(
        totalTokens: 350,
        inputTokens: 100,
        outputTokens: 250,
        durationMs: 5000,
        toolCalls: 2,
      );

      expect(stats.totalTokens, 350);
      expect(stats.inputTokens, 100);
      expect(stats.outputTokens, 250);
      expect(stats.durationMs, 5000);
      expect(stats.toolCalls, 2);
    });

    test('serializes to JSON', () {
      final stats = GeminiStats(
        totalTokens: 500,
        inputTokens: 200,
        outputTokens: 300,
        durationMs: 3000,
        toolCalls: 1,
      );

      final json = stats.toJson();
      expect(json['totalTokens'], 500);
      expect(json['inputTokens'], 200);
      expect(json['outputTokens'], 300);
      expect(json['durationMs'], 3000);
      expect(json['toolCalls'], 1);
    });

    test('deserializes from JSON', () {
      final json = {
        'totalTokens': 1000,
        'inputTokens': 400,
        'outputTokens': 600,
        'durationMs': 10000,
        'toolCalls': 5,
      };

      final stats = GeminiStats.fromJson(json);
      expect(stats.totalTokens, 1000);
      expect(stats.inputTokens, 400);
      expect(stats.outputTokens, 600);
      expect(stats.durationMs, 10000);
      expect(stats.toolCalls, 5);
    });
  });

  group('GeminiToolUse', () {
    test('constructs correctly', () {
      final toolUse = GeminiToolUse(
        toolName: 'Bash',
        toolId: 'bash_01',
        parameters: {'command': 'ls -la'},
      );

      expect(toolUse.toolName, 'Bash');
      expect(toolUse.toolId, 'bash_01');
      expect(toolUse.parameters['command'], 'ls -la');
    });

    test('serializes to JSON', () {
      final toolUse = GeminiToolUse(
        toolName: 'Read',
        toolId: 'read_01',
        parameters: {'file_path': '/test.txt'},
      );

      final json = toolUse.toJson();
      expect(json['toolName'], 'Read');
      expect(json['toolId'], 'read_01');
      expect(json['parameters']['file_path'], '/test.txt');
    });

    test('deserializes from JSON', () {
      final json = {
        'toolName': 'Write',
        'toolId': 'write_01',
        'parameters': {'file_path': '/out.txt', 'content': 'Hello'},
      };

      final toolUse = GeminiToolUse.fromJson(json);
      expect(toolUse.toolName, 'Write');
      expect(toolUse.toolId, 'write_01');
      expect(toolUse.parameters['content'], 'Hello');
    });
  });

  group('GeminiToolResult', () {
    test('constructs with success', () {
      final result = GeminiToolResult(
        toolId: 'tool_01',
        status: 'success',
        output: 'file contents here',
      );

      expect(result.toolId, 'tool_01');
      expect(result.status, 'success');
      expect(result.output, 'file contents here');
      expect(result.error, isNull);
    });

    test('constructs with error', () {
      final result = GeminiToolResult(
        toolId: 'tool_01',
        status: 'error',
        error: {'type': 'file_not_found', 'message': 'File does not exist'},
      );

      expect(result.toolId, 'tool_01');
      expect(result.status, 'error');
      expect(result.output, isNull);
      expect(result.error!['type'], 'file_not_found');
    });

    test('serializes to JSON', () {
      final result = GeminiToolResult(
        toolId: 'tool_02',
        status: 'success',
        output: 'result data',
      );

      final json = result.toJson();
      expect(json['toolId'], 'tool_02');
      expect(json['status'], 'success');
      expect(json['output'], 'result data');
    });

    test('deserializes from JSON', () {
      final json = {
        'toolId': 'tool_03',
        'status': 'error',
        'error': {'message': 'Permission denied'},
      };

      final result = GeminiToolResult.fromJson(json);
      expect(result.toolId, 'tool_03');
      expect(result.status, 'error');
      expect(result.error!['message'], 'Permission denied');
    });
  });
}
