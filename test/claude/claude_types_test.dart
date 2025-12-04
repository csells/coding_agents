import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/claude/claude_types.dart';

void main() {
  group('ClaudePermissionMode', () {
    test('has all expected values', () {
      expect(ClaudePermissionMode.values, hasLength(4));
      expect(ClaudePermissionMode.values, contains(ClaudePermissionMode.defaultMode));
      expect(ClaudePermissionMode.values, contains(ClaudePermissionMode.acceptEdits));
      expect(ClaudePermissionMode.values, contains(ClaudePermissionMode.bypassPermissions));
      expect(ClaudePermissionMode.values, contains(ClaudePermissionMode.delegate));
    });
  });

  group('ClaudePermissionBehavior', () {
    test('has all expected values', () {
      expect(ClaudePermissionBehavior.values, hasLength(4));
      expect(ClaudePermissionBehavior.values, contains(ClaudePermissionBehavior.allow));
      expect(ClaudePermissionBehavior.values, contains(ClaudePermissionBehavior.deny));
      expect(ClaudePermissionBehavior.values, contains(ClaudePermissionBehavior.allowAlways));
      expect(ClaudePermissionBehavior.values, contains(ClaudePermissionBehavior.denyAlways));
    });
  });

  group('ClaudeSessionInfo', () {
    test('constructs with required fields', () {
      final info = ClaudeSessionInfo(
        sessionId: 'sess_123',
        cwd: '/path/to/project',
        timestamp: DateTime(2025, 1, 1),
        lastUpdated: DateTime(2025, 1, 2),
      );

      expect(info.sessionId, 'sess_123');
      expect(info.cwd, '/path/to/project');
      expect(info.gitBranch, isNull);
      expect(info.timestamp, DateTime(2025, 1, 1));
      expect(info.lastUpdated, DateTime(2025, 1, 2));
    });

    test('constructs with optional gitBranch', () {
      final info = ClaudeSessionInfo(
        sessionId: 'sess_123',
        cwd: '/path/to/project',
        gitBranch: 'main',
        timestamp: DateTime(2025, 1, 1),
        lastUpdated: DateTime(2025, 1, 2),
      );

      expect(info.gitBranch, 'main');
    });

    test('serializes to JSON', () {
      final info = ClaudeSessionInfo(
        sessionId: 'sess_123',
        cwd: '/path/to/project',
        gitBranch: 'main',
        timestamp: DateTime.utc(2025, 1, 1),
        lastUpdated: DateTime.utc(2025, 1, 2),
      );

      final json = info.toJson();
      expect(json['sessionId'], 'sess_123');
      expect(json['cwd'], '/path/to/project');
      expect(json['gitBranch'], 'main');
    });

    test('deserializes from JSON', () {
      final json = {
        'sessionId': 'sess_456',
        'cwd': '/another/path',
        'gitBranch': 'feature',
        'timestamp': '2025-01-01T00:00:00.000Z',
        'lastUpdated': '2025-01-02T00:00:00.000Z',
      };

      final info = ClaudeSessionInfo.fromJson(json);
      expect(info.sessionId, 'sess_456');
      expect(info.cwd, '/another/path');
      expect(info.gitBranch, 'feature');
    });
  });

  group('ClaudeUsage', () {
    test('constructs with required fields', () {
      final usage = ClaudeUsage(inputTokens: 100, outputTokens: 50);

      expect(usage.inputTokens, 100);
      expect(usage.outputTokens, 50);
      expect(usage.cacheCreationInputTokens, isNull);
      expect(usage.cacheReadInputTokens, isNull);
    });

    test('constructs with cache tokens', () {
      final usage = ClaudeUsage(
        inputTokens: 100,
        outputTokens: 50,
        cacheCreationInputTokens: 25,
        cacheReadInputTokens: 10,
      );

      expect(usage.cacheCreationInputTokens, 25);
      expect(usage.cacheReadInputTokens, 10);
    });

    test('serializes to JSON', () {
      final usage = ClaudeUsage(inputTokens: 100, outputTokens: 50);
      final json = usage.toJson();

      expect(json['input_tokens'], 100);
      expect(json['output_tokens'], 50);
    });

    test('deserializes from JSON', () {
      final json = {
        'inputTokens': 200,
        'outputTokens': 100,
        'cacheCreationInputTokens': 50,
        'cacheReadInputTokens': 25,
      };

      final usage = ClaudeUsage.fromJson(json);
      expect(usage.inputTokens, 200);
      expect(usage.outputTokens, 100);
      expect(usage.cacheCreationInputTokens, 50);
      expect(usage.cacheReadInputTokens, 25);
    });
  });

  group('ClaudeContentBlock', () {
    test('parses text block', () {
      final json = {'type': 'text', 'text': 'Hello world'};
      final block = ClaudeContentBlock.fromJson(json);

      expect(block, isA<ClaudeTextBlock>());
      expect((block as ClaudeTextBlock).text, 'Hello world');
    });

    test('parses thinking block', () {
      final json = {'type': 'thinking', 'thinking': 'Let me analyze...'};
      final block = ClaudeContentBlock.fromJson(json);

      expect(block, isA<ClaudeThinkingBlock>());
      expect((block as ClaudeThinkingBlock).thinking, 'Let me analyze...');
    });

    test('parses tool_use block', () {
      final json = {
        'type': 'tool_use',
        'id': 'toolu_01',
        'name': 'Read',
        'input': {'file_path': '/test.txt'},
      };
      final block = ClaudeContentBlock.fromJson(json);

      expect(block, isA<ClaudeToolUseBlock>());
      final toolUse = block as ClaudeToolUseBlock;
      expect(toolUse.id, 'toolu_01');
      expect(toolUse.name, 'Read');
      expect(toolUse.input['file_path'], '/test.txt');
    });

    test('parses tool_result block', () {
      final json = {
        'type': 'tool_result',
        'toolUseId': 'toolu_01',
        'content': 'File contents here',
        'isError': false,
      };
      final block = ClaudeContentBlock.fromJson(json);

      expect(block, isA<ClaudeToolResultBlock>());
      final result = block as ClaudeToolResultBlock;
      expect(result.toolUseId, 'toolu_01');
      expect(result.content, 'File contents here');
      expect(result.isError, false);
    });

    test('parses unknown block type', () {
      final json = {'type': 'future_type', 'data': 'something'};
      final block = ClaudeContentBlock.fromJson(json);

      expect(block, isA<ClaudeUnknownBlock>());
      expect((block as ClaudeUnknownBlock).type, 'future_type');
    });
  });

  group('ClaudeToolPermissionRequest', () {
    test('constructs correctly', () {
      final request = ClaudeToolPermissionRequest(
        toolName: 'Bash',
        toolInput: {'command': 'ls -la'},
        sessionId: 'sess_123',
        turnId: 5,
      );

      expect(request.toolName, 'Bash');
      expect(request.toolInput['command'], 'ls -la');
      expect(request.sessionId, 'sess_123');
      expect(request.turnId, 5);
    });

    test('serializes to JSON', () {
      final request = ClaudeToolPermissionRequest(
        toolName: 'Edit',
        toolInput: {'file_path': '/test.txt'},
        sessionId: 'sess_456',
        turnId: 3,
      );

      final json = request.toJson();
      expect(json['toolName'], 'Edit');
      expect(json['sessionId'], 'sess_456');
    });
  });

  group('ClaudeToolPermissionResponse', () {
    test('constructs with allow behavior', () {
      final response = ClaudeToolPermissionResponse(
        behavior: ClaudePermissionBehavior.allow,
      );

      expect(response.behavior, ClaudePermissionBehavior.allow);
      expect(response.updatedInput, isNull);
      expect(response.message, isNull);
    });

    test('constructs with deny behavior and message', () {
      final response = ClaudeToolPermissionResponse(
        behavior: ClaudePermissionBehavior.deny,
        message: 'Operation not allowed',
      );

      expect(response.behavior, ClaudePermissionBehavior.deny);
      expect(response.message, 'Operation not allowed');
    });

    test('constructs with updated input', () {
      final response = ClaudeToolPermissionResponse(
        behavior: ClaudePermissionBehavior.allow,
        updatedInput: {'file_path': '/safe/path.txt'},
      );

      expect(response.updatedInput, {'file_path': '/safe/path.txt'});
    });
  });
}
