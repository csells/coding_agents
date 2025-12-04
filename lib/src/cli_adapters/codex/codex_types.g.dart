// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'codex_types.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CodexSessionInfo _$CodexSessionInfoFromJson(Map<String, dynamic> json) =>
    CodexSessionInfo(
      threadId: json['threadId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      gitBranch: json['gitBranch'] as String?,
      repositoryUrl: json['repositoryUrl'] as String?,
      cwd: json['cwd'] as String?,
    );

Map<String, dynamic> _$CodexSessionInfoToJson(CodexSessionInfo instance) =>
    <String, dynamic>{
      'threadId': instance.threadId,
      'timestamp': instance.timestamp.toIso8601String(),
      'lastUpdated': instance.lastUpdated.toIso8601String(),
      'gitBranch': instance.gitBranch,
      'repositoryUrl': instance.repositoryUrl,
      'cwd': instance.cwd,
    };

CodexAgentMessageItem _$CodexAgentMessageItemFromJson(
  Map<String, dynamic> json,
) => CodexAgentMessageItem(
  id: json['id'] as String,
  text: json['text'] as String,
);

Map<String, dynamic> _$CodexAgentMessageItemToJson(
  CodexAgentMessageItem instance,
) => <String, dynamic>{'id': instance.id, 'text': instance.text};

CodexToolCallItem _$CodexToolCallItemFromJson(Map<String, dynamic> json) =>
    CodexToolCallItem(
      id: json['id'] as String,
      name: json['name'] as String,
      arguments: json['arguments'] as Map<String, dynamic>,
      output: json['output'] as String?,
      exitCode: (json['exit_code'] as num?)?.toInt(),
    );

Map<String, dynamic> _$CodexToolCallItemToJson(CodexToolCallItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'arguments': instance.arguments,
      'output': instance.output,
      'exit_code': instance.exitCode,
    };

CodexFileChangeItem _$CodexFileChangeItemFromJson(Map<String, dynamic> json) =>
    CodexFileChangeItem(
      id: json['id'] as String,
      path: json['path'] as String,
      before: json['before'] as String?,
      after: json['after'] as String?,
      diff: json['diff'] as String?,
    );

Map<String, dynamic> _$CodexFileChangeItemToJson(
  CodexFileChangeItem instance,
) => <String, dynamic>{
  'id': instance.id,
  'path': instance.path,
  'before': instance.before,
  'after': instance.after,
  'diff': instance.diff,
};

CodexMcpToolCallItem _$CodexMcpToolCallItemFromJson(
  Map<String, dynamic> json,
) => CodexMcpToolCallItem(
  id: json['id'] as String,
  toolName: json['tool_name'] as String,
  toolInput: json['tool_input'] as Map<String, dynamic>,
  toolResult: json['tool_result'],
);

Map<String, dynamic> _$CodexMcpToolCallItemToJson(
  CodexMcpToolCallItem instance,
) => <String, dynamic>{
  'id': instance.id,
  'tool_name': instance.toolName,
  'tool_input': instance.toolInput,
  'tool_result': instance.toolResult,
};

CodexWebSearchItem _$CodexWebSearchItemFromJson(Map<String, dynamic> json) =>
    CodexWebSearchItem(
      id: json['id'] as String,
      query: json['query'] as String,
      results: json['results'] as List<dynamic>,
    );

Map<String, dynamic> _$CodexWebSearchItemToJson(CodexWebSearchItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'query': instance.query,
      'results': instance.results,
    };

CodexTodoListItem _$CodexTodoListItemFromJson(Map<String, dynamic> json) =>
    CodexTodoListItem(
      id: json['id'] as String,
      items: json['items'] as List<dynamic>,
    );

Map<String, dynamic> _$CodexTodoListItemToJson(CodexTodoListItem instance) =>
    <String, dynamic>{'id': instance.id, 'items': instance.items};
