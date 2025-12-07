import 'package:json_annotation/json_annotation.dart';

part 'codex_types.g.dart';

/// Approval policy for Codex CLI tool executions
enum CodexApprovalPolicy { onRequest, untrusted, onFailure, never }

/// Sandbox mode for Codex CLI
enum CodexSandboxMode { readOnly, workspaceWrite, dangerFullAccess }

/// Permission behavior response values for approval decisions
enum CodexApprovalDecision {
  /// Allow this specific action
  allow,

  /// Deny this specific action
  deny,

  /// Allow this action and all future similar actions
  allowAlways,

  /// Deny this action and all future similar actions
  denyAlways,
}

/// Item types in Codex output
enum CodexItemType {
  agentMessage,
  reasoning,
  toolCall,
  fileChange,
  mcpToolCall,
  webSearch,
  todoList,
  error,
}

/// Information about a Codex session
@JsonSerializable()
class CodexSessionInfo {
  final String threadId;
  final DateTime timestamp;
  final DateTime lastUpdated;
  final String? gitBranch;
  final String? repositoryUrl;
  final String? cwd;

  CodexSessionInfo({
    required this.threadId,
    required this.timestamp,
    required this.lastUpdated,
    this.gitBranch,
    this.repositoryUrl,
    this.cwd,
  });

  factory CodexSessionInfo.fromJson(Map<String, dynamic> json) =>
      _$CodexSessionInfoFromJson(json);

  Map<String, dynamic> toJson() => _$CodexSessionInfoToJson(this);
}

/// Token usage statistics for a Codex turn
class CodexUsage {
  final int inputTokens;
  final int outputTokens;
  final int? cachedInputTokens;

  CodexUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.cachedInputTokens,
  });

  /// Parse from JSON, handling both snake_case (Codex API) and camelCase
  factory CodexUsage.fromJson(Map<String, dynamic> json) => CodexUsage(
    inputTokens:
        (json['input_tokens'] as num?)?.toInt() ??
        (json['inputTokens'] as num?)?.toInt() ??
        0,
    outputTokens:
        (json['output_tokens'] as num?)?.toInt() ??
        (json['outputTokens'] as num?)?.toInt() ??
        0,
    cachedInputTokens:
        (json['cached_input_tokens'] as num?)?.toInt() ??
        (json['cachedInputTokens'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    if (cachedInputTokens != null) 'cached_input_tokens': cachedInputTokens,
  };
}

/// Base class for Codex output items
sealed class CodexItem {
  String get id;
  CodexItemType get type;

  factory CodexItem.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String?;

    switch (typeStr) {
      case 'agent_message':
        return CodexAgentMessageItem.fromJson(json);
      case 'reasoning':
        return CodexReasoningItem.fromJson(json);
      case 'tool_call':
      case 'shell':
        return CodexToolCallItem.fromJson(json);
      case 'file_change':
        return CodexFileChangeItem.fromJson(json);
      case 'mcp_tool_call':
        return CodexMcpToolCallItem.fromJson(json);
      case 'web_search':
        return CodexWebSearchItem.fromJson(json);
      case 'todo_list':
        return CodexTodoListItem.fromJson(json);
      default:
        return CodexUnknownItem(data: json);
    }
  }
}

/// Agent message item
@JsonSerializable()
class CodexAgentMessageItem implements CodexItem {
  @override
  final String id;
  final String text;

  @override
  CodexItemType get type => CodexItemType.agentMessage;

  CodexAgentMessageItem({required this.id, required this.text});

  factory CodexAgentMessageItem.fromJson(Map<String, dynamic> json) =>
      _$CodexAgentMessageItemFromJson(json);

  Map<String, dynamic> toJson() => _$CodexAgentMessageItemToJson(this);
}

/// Reasoning item (thinking/chain-of-thought)
class CodexReasoningItem implements CodexItem {
  @override
  final String id;
  final String? reasoning;
  final String? summary;

  @override
  CodexItemType get type => CodexItemType.reasoning;

  CodexReasoningItem({required this.id, this.reasoning, this.summary});

  factory CodexReasoningItem.fromJson(Map<String, dynamic> json) =>
      CodexReasoningItem(
        id: json['id'] as String? ?? '',
        reasoning: json['reasoning'] as String?,
        summary: json['summary'] as String?,
      );
}

/// Tool call item (shell commands, etc.)
@JsonSerializable()
class CodexToolCallItem implements CodexItem {
  @override
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String? output;
  @JsonKey(name: 'exit_code')
  final int? exitCode;

  @override
  CodexItemType get type => CodexItemType.toolCall;

  CodexToolCallItem({
    required this.id,
    required this.name,
    required this.arguments,
    this.output,
    this.exitCode,
  });

  factory CodexToolCallItem.fromJson(Map<String, dynamic> json) =>
      _$CodexToolCallItemFromJson(json);

  Map<String, dynamic> toJson() => _$CodexToolCallItemToJson(this);
}

/// File change item
@JsonSerializable()
class CodexFileChangeItem implements CodexItem {
  @override
  final String id;
  final String path;
  final String? before;
  final String? after;
  final String? diff;

  @override
  CodexItemType get type => CodexItemType.fileChange;

  CodexFileChangeItem({
    required this.id,
    required this.path,
    this.before,
    this.after,
    this.diff,
  });

  factory CodexFileChangeItem.fromJson(Map<String, dynamic> json) =>
      _$CodexFileChangeItemFromJson(json);

  Map<String, dynamic> toJson() => _$CodexFileChangeItemToJson(this);
}

/// MCP tool call item
@JsonSerializable()
class CodexMcpToolCallItem implements CodexItem {
  @override
  final String id;
  @JsonKey(name: 'tool_name')
  final String toolName;
  @JsonKey(name: 'tool_input')
  final Map<String, dynamic> toolInput;
  @JsonKey(name: 'tool_result')
  final dynamic toolResult;

  @override
  CodexItemType get type => CodexItemType.mcpToolCall;

  CodexMcpToolCallItem({
    required this.id,
    required this.toolName,
    required this.toolInput,
    this.toolResult,
  });

  factory CodexMcpToolCallItem.fromJson(Map<String, dynamic> json) =>
      _$CodexMcpToolCallItemFromJson(json);

  Map<String, dynamic> toJson() => _$CodexMcpToolCallItemToJson(this);
}

/// Web search item
@JsonSerializable()
class CodexWebSearchItem implements CodexItem {
  @override
  final String id;
  final String query;
  final List<dynamic> results;

  @override
  CodexItemType get type => CodexItemType.webSearch;

  CodexWebSearchItem({
    required this.id,
    required this.query,
    required this.results,
  });

  factory CodexWebSearchItem.fromJson(Map<String, dynamic> json) =>
      _$CodexWebSearchItemFromJson(json);

  Map<String, dynamic> toJson() => _$CodexWebSearchItemToJson(this);
}

/// Todo list item
@JsonSerializable()
class CodexTodoListItem implements CodexItem {
  @override
  final String id;
  final List<dynamic> items;

  @override
  CodexItemType get type => CodexItemType.todoList;

  CodexTodoListItem({required this.id, required this.items});

  factory CodexTodoListItem.fromJson(Map<String, dynamic> json) =>
      _$CodexTodoListItemFromJson(json);

  Map<String, dynamic> toJson() => _$CodexTodoListItemToJson(this);
}

/// Unknown item type for forward compatibility
class CodexUnknownItem implements CodexItem {
  final Map<String, dynamic> data;

  @override
  String get id => data['id'] as String? ?? '';

  @override
  CodexItemType get type => CodexItemType.error;

  CodexUnknownItem({required this.data});
}

/// Approval request from Codex app-server
///
/// When the app-server needs approval for a tool execution, it emits
/// an approval item and waits for the client to send a decision.
@JsonSerializable()
class CodexApprovalRequest {
  /// Unique ID for this approval request
  final String id;

  /// Turn ID this approval is associated with
  final String turnId;

  /// Type of action requiring approval (e.g., 'shell', 'file_write')
  final String actionType;

  /// Human-readable description of the action
  final String description;

  /// Tool name (e.g., 'bash', 'write')
  final String? toolName;

  /// Tool input/arguments
  final Map<String, dynamic>? toolInput;

  /// Command to be executed (for shell actions)
  final String? command;

  /// File path (for file operations)
  final String? filePath;

  CodexApprovalRequest({
    required this.id,
    required this.turnId,
    required this.actionType,
    required this.description,
    this.toolName,
    this.toolInput,
    this.command,
    this.filePath,
  });

  factory CodexApprovalRequest.fromJson(Map<String, dynamic> json) =>
      _$CodexApprovalRequestFromJson(json);

  Map<String, dynamic> toJson() => _$CodexApprovalRequestToJson(this);
}

/// Response to an approval request
@JsonSerializable()
class CodexApprovalResponse {
  /// The decision for this approval
  final CodexApprovalDecision decision;

  /// Optional message to include with the response
  final String? message;

  CodexApprovalResponse({required this.decision, this.message});

  factory CodexApprovalResponse.fromJson(Map<String, dynamic> json) =>
      _$CodexApprovalResponseFromJson(json);

  Map<String, dynamic> toJson() => _$CodexApprovalResponseToJson(this);
}
