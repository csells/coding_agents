import 'package:test/test.dart';
import 'package:coding_agents/src/cli_adapters/codex/codex_types.dart';

void main() {
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

  group('CodexItemType', () {
    test('has all expected values', () {
      expect(CodexItemType.values, hasLength(8));
      expect(CodexItemType.values, contains(CodexItemType.agentMessage));
      expect(CodexItemType.values, contains(CodexItemType.reasoning));
      expect(CodexItemType.values, contains(CodexItemType.toolCall));
      expect(CodexItemType.values, contains(CodexItemType.fileChange));
      expect(CodexItemType.values, contains(CodexItemType.mcpToolCall));
      expect(CodexItemType.values, contains(CodexItemType.webSearch));
      expect(CodexItemType.values, contains(CodexItemType.todoList));
      expect(CodexItemType.values, contains(CodexItemType.error));
    });
  });

  group('CodexSessionInfo', () {
    test('constructs with required fields', () {
      final info = CodexSessionInfo(
        threadId: 'thread_123',
        timestamp: DateTime(2025, 1, 1),
        lastUpdated: DateTime(2025, 1, 2),
      );

      expect(info.threadId, 'thread_123');
      expect(info.timestamp, DateTime(2025, 1, 1));
      expect(info.lastUpdated, DateTime(2025, 1, 2));
      expect(info.gitBranch, isNull);
      expect(info.repositoryUrl, isNull);
      expect(info.cwd, isNull);
    });

    test('constructs with optional fields', () {
      final info = CodexSessionInfo(
        threadId: 'thread_123',
        timestamp: DateTime(2025, 1, 1),
        lastUpdated: DateTime(2025, 1, 2),
        gitBranch: 'main',
        repositoryUrl: 'https://github.com/user/repo',
        cwd: '/path/to/project',
      );

      expect(info.gitBranch, 'main');
      expect(info.repositoryUrl, 'https://github.com/user/repo');
      expect(info.cwd, '/path/to/project');
    });

    test('serializes to JSON', () {
      final info = CodexSessionInfo(
        threadId: 'thread_456',
        timestamp: DateTime.utc(2025, 1, 1),
        lastUpdated: DateTime.utc(2025, 1, 2),
        cwd: '/test',
      );

      final json = info.toJson();
      expect(json['threadId'], 'thread_456');
      expect(json['cwd'], '/test');
    });

    test('deserializes from JSON', () {
      final json = {
        'threadId': 'thread_789',
        'timestamp': '2025-01-01T00:00:00.000Z',
        'lastUpdated': '2025-01-02T00:00:00.000Z',
        'gitBranch': 'feature',
        'cwd': '/project',
      };

      final info = CodexSessionInfo.fromJson(json);
      expect(info.threadId, 'thread_789');
      expect(info.gitBranch, 'feature');
      expect(info.cwd, '/project');
    });
  });

  group('CodexUsage', () {
    test('constructs with required fields', () {
      final usage = CodexUsage(inputTokens: 100, outputTokens: 50);

      expect(usage.inputTokens, 100);
      expect(usage.outputTokens, 50);
      expect(usage.cachedInputTokens, isNull);
    });

    test('constructs with cached tokens', () {
      final usage = CodexUsage(
        inputTokens: 100,
        outputTokens: 50,
        cachedInputTokens: 25,
      );

      expect(usage.cachedInputTokens, 25);
    });

    test('serializes to JSON', () {
      final usage = CodexUsage(inputTokens: 100, outputTokens: 50);
      final json = usage.toJson();

      expect(json['input_tokens'], 100);
      expect(json['output_tokens'], 50);
    });

    test('deserializes from JSON', () {
      final json = {
        'inputTokens': 200,
        'outputTokens': 100,
        'cachedInputTokens': 50,
      };

      final usage = CodexUsage.fromJson(json);
      expect(usage.inputTokens, 200);
      expect(usage.cachedInputTokens, 50);
    });
  });

  group('CodexItem.fromJson', () {
    test('parses agent_message item', () {
      final json = {
        'type': 'agent_message',
        'id': 'msg_01',
        'text': 'I will help you with that.',
      };

      final item = CodexItem.fromJson(json);

      expect(item, isA<CodexAgentMessageItem>());
      final msg = item as CodexAgentMessageItem;
      expect(msg.id, 'msg_01');
      expect(msg.text, 'I will help you with that.');
      expect(msg.type, CodexItemType.agentMessage);
    });

    test('parses reasoning item', () {
      final json = {
        'type': 'reasoning',
        'id': 'reason_01',
        'reasoning': 'Let me think about this step by step...',
        'summary': 'Analyzing the problem',
      };

      final item = CodexItem.fromJson(json);

      expect(item, isA<CodexReasoningItem>());
      final reasoning = item as CodexReasoningItem;
      expect(reasoning.reasoning, 'Let me think about this step by step...');
      expect(reasoning.summary, 'Analyzing the problem');
    });

    test('parses tool_call item', () {
      final json = {
        'type': 'tool_call',
        'id': 'tool_01',
        'name': 'shell',
        'arguments': {'command': 'ls -la'},
        'output': 'file1.txt\nfile2.txt',
        'exit_code': 0,
      };

      final item = CodexItem.fromJson(json);

      expect(item, isA<CodexToolCallItem>());
      final toolCall = item as CodexToolCallItem;
      expect(toolCall.name, 'shell');
      expect(toolCall.arguments['command'], 'ls -la');
      expect(toolCall.output, 'file1.txt\nfile2.txt');
      expect(toolCall.exitCode, 0);
    });

    test('parses shell item as tool_call', () {
      final json = {
        'type': 'shell',
        'id': 'shell_01',
        'name': 'shell',
        'arguments': {'command': 'npm test'},
      };

      final item = CodexItem.fromJson(json);
      expect(item, isA<CodexToolCallItem>());
    });

    test('parses file_change item', () {
      final json = {
        'type': 'file_change',
        'id': 'file_01',
        'path': 'src/main.dart',
        'before': 'old content',
        'after': 'new content',
        'diff': '@@ -1 +1 @@\n-old content\n+new content',
      };

      final item = CodexItem.fromJson(json);

      expect(item, isA<CodexFileChangeItem>());
      final fileChange = item as CodexFileChangeItem;
      expect(fileChange.path, 'src/main.dart');
      expect(fileChange.before, 'old content');
      expect(fileChange.after, 'new content');
      expect(fileChange.diff, contains('@@'));
    });

    test('parses mcp_tool_call item', () {
      final json = {
        'type': 'mcp_tool_call',
        'id': 'mcp_01',
        'tool_name': 'database_query',
        'tool_input': {'sql': 'SELECT * FROM users'},
        'tool_result': [{'id': 1, 'name': 'Alice'}],
      };

      final item = CodexItem.fromJson(json);

      expect(item, isA<CodexMcpToolCallItem>());
      final mcpCall = item as CodexMcpToolCallItem;
      expect(mcpCall.toolName, 'database_query');
      expect(mcpCall.toolInput['sql'], 'SELECT * FROM users');
    });

    test('parses web_search item', () {
      final json = {
        'type': 'web_search',
        'id': 'search_01',
        'query': 'dart async best practices',
        'results': [
          {'title': 'Dart Async Guide', 'url': 'https://dart.dev/async'},
        ],
      };

      final item = CodexItem.fromJson(json);

      expect(item, isA<CodexWebSearchItem>());
      final search = item as CodexWebSearchItem;
      expect(search.query, 'dart async best practices');
      expect(search.results, hasLength(1));
    });

    test('parses todo_list item', () {
      final json = {
        'type': 'todo_list',
        'id': 'todo_01',
        'items': [
          {'id': '1', 'task': 'Fix bug', 'status': 'completed'},
          {'id': '2', 'task': 'Add tests', 'status': 'pending'},
        ],
      };

      final item = CodexItem.fromJson(json);

      expect(item, isA<CodexTodoListItem>());
      final todoList = item as CodexTodoListItem;
      expect(todoList.items, hasLength(2));
    });

    test('parses unknown item type as CodexUnknownItem', () {
      final json = {
        'type': 'future_type',
        'id': 'unknown_01',
        'data': 'some value',
      };

      final item = CodexItem.fromJson(json);

      expect(item, isA<CodexUnknownItem>());
      final unknown = item as CodexUnknownItem;
      expect(unknown.data['type'], 'future_type');
    });
  });
}
