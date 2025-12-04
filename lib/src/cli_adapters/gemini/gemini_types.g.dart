// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gemini_types.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GeminiSessionInfo _$GeminiSessionInfoFromJson(Map<String, dynamic> json) =>
    GeminiSessionInfo(
      sessionId: json['sessionId'] as String,
      projectHash: json['projectHash'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      messageCount: (json['messageCount'] as num).toInt(),
    );

Map<String, dynamic> _$GeminiSessionInfoToJson(GeminiSessionInfo instance) =>
    <String, dynamic>{
      'sessionId': instance.sessionId,
      'projectHash': instance.projectHash,
      'startTime': instance.startTime.toIso8601String(),
      'lastUpdated': instance.lastUpdated.toIso8601String(),
      'messageCount': instance.messageCount,
    };

GeminiToolUse _$GeminiToolUseFromJson(Map<String, dynamic> json) =>
    GeminiToolUse(
      toolName: json['toolName'] as String,
      toolId: json['toolId'] as String,
      parameters: json['parameters'] as Map<String, dynamic>,
    );

Map<String, dynamic> _$GeminiToolUseToJson(GeminiToolUse instance) =>
    <String, dynamic>{
      'toolName': instance.toolName,
      'toolId': instance.toolId,
      'parameters': instance.parameters,
    };

GeminiToolResult _$GeminiToolResultFromJson(Map<String, dynamic> json) =>
    GeminiToolResult(
      toolId: json['toolId'] as String,
      status: json['status'] as String,
      output: json['output'] as String?,
      error: json['error'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$GeminiToolResultToJson(GeminiToolResult instance) =>
    <String, dynamic>{
      'toolId': instance.toolId,
      'status': instance.status,
      'output': instance.output,
      'error': instance.error,
    };

GenerateContentResponse _$GenerateContentResponseFromJson(
  Map<String, dynamic> json,
) => GenerateContentResponse(
  text: json['text'] as String?,
  prompt: json['prompt'] as String?,
  stats: GeminiStats.fromJson(json['stats'] as Map<String, dynamic>),
  toolCalls:
      (json['toolCalls'] as List<dynamic>?)
          ?.map((e) => GeminiToolUse.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  toolResults:
      (json['toolResults'] as List<dynamic>?)
          ?.map((e) => GeminiToolResult.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$GenerateContentResponseToJson(
  GenerateContentResponse instance,
) => <String, dynamic>{
  'text': instance.text,
  'prompt': instance.prompt,
  'stats': instance.stats,
  'toolCalls': instance.toolCalls,
  'toolResults': instance.toolResults,
};

GeminiSessionConfig _$GeminiSessionConfigFromJson(Map<String, dynamic> json) =>
    GeminiSessionConfig(
      approvalMode:
          $enumDecodeNullable(
            _$GeminiApprovalModeEnumMap,
            json['approvalMode'],
          ) ??
          GeminiApprovalMode.defaultMode,
      sandbox: json['sandbox'] as bool? ?? false,
      sandboxImage: json['sandboxImage'] as String?,
      model: json['model'] as String?,
      debug: json['debug'] as bool? ?? false,
    );

Map<String, dynamic> _$GeminiSessionConfigToJson(
  GeminiSessionConfig instance,
) => <String, dynamic>{
  'approvalMode': _$GeminiApprovalModeEnumMap[instance.approvalMode]!,
  'sandbox': instance.sandbox,
  'sandboxImage': instance.sandboxImage,
  'model': instance.model,
  'debug': instance.debug,
};

const _$GeminiApprovalModeEnumMap = {
  GeminiApprovalMode.defaultMode: 'defaultMode',
  GeminiApprovalMode.autoEdit: 'autoEdit',
  GeminiApprovalMode.yolo: 'yolo',
};

ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) => ChatMessage(
  role: $enumDecode(_$ChatRoleEnumMap, json['role']),
  text: json['text'] as String,
);

Map<String, dynamic> _$ChatMessageToJson(ChatMessage instance) =>
    <String, dynamic>{
      'role': _$ChatRoleEnumMap[instance.role]!,
      'text': instance.text,
    };

const _$ChatRoleEnumMap = {ChatRole.user: 'user', ChatRole.model: 'model'};

ChatRequest _$ChatRequestFromJson(Map<String, dynamic> json) => ChatRequest(
  messages: (json['messages'] as List<dynamic>)
      .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
      .toList(),
  config: GeminiSessionConfig.fromJson(json['config'] as Map<String, dynamic>),
);

Map<String, dynamic> _$ChatRequestToJson(ChatRequest instance) =>
    <String, dynamic>{'messages': instance.messages, 'config': instance.config};
