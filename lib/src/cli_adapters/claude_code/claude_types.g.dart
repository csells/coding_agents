// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'claude_types.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ClaudeSessionInfo _$ClaudeSessionInfoFromJson(Map<String, dynamic> json) =>
    ClaudeSessionInfo(
      sessionId: json['sessionId'] as String,
      cwd: json['cwd'] as String,
      gitBranch: json['gitBranch'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
    );

Map<String, dynamic> _$ClaudeSessionInfoToJson(ClaudeSessionInfo instance) =>
    <String, dynamic>{
      'sessionId': instance.sessionId,
      'cwd': instance.cwd,
      'gitBranch': instance.gitBranch,
      'timestamp': instance.timestamp.toIso8601String(),
      'lastUpdated': instance.lastUpdated.toIso8601String(),
    };

ClaudeToolPermissionRequest _$ClaudeToolPermissionRequestFromJson(
  Map<String, dynamic> json,
) => ClaudeToolPermissionRequest(
  toolName: json['toolName'] as String,
  toolInput: json['toolInput'] as Map<String, dynamic>,
  sessionId: json['sessionId'] as String,
  turnId: (json['turnId'] as num).toInt(),
  toolUseId: json['toolUseId'] as String?,
  blockedPath: json['blockedPath'] as String?,
  decisionReason: json['decisionReason'] as String?,
);

Map<String, dynamic> _$ClaudeToolPermissionRequestToJson(
  ClaudeToolPermissionRequest instance,
) => <String, dynamic>{
  'toolName': instance.toolName,
  'toolInput': instance.toolInput,
  'sessionId': instance.sessionId,
  'turnId': instance.turnId,
  'toolUseId': instance.toolUseId,
  'blockedPath': instance.blockedPath,
  'decisionReason': instance.decisionReason,
};

ClaudeToolPermissionResponse _$ClaudeToolPermissionResponseFromJson(
  Map<String, dynamic> json,
) => ClaudeToolPermissionResponse(
  behavior: $enumDecode(_$ClaudePermissionBehaviorEnumMap, json['behavior']),
  updatedInput: json['updatedInput'] as Map<String, dynamic>?,
  message: json['message'] as String?,
);

Map<String, dynamic> _$ClaudeToolPermissionResponseToJson(
  ClaudeToolPermissionResponse instance,
) => <String, dynamic>{
  'behavior': _$ClaudePermissionBehaviorEnumMap[instance.behavior]!,
  'updatedInput': instance.updatedInput,
  'message': instance.message,
};

const _$ClaudePermissionBehaviorEnumMap = {
  ClaudePermissionBehavior.allow: 'allow',
  ClaudePermissionBehavior.deny: 'deny',
  ClaudePermissionBehavior.allowAlways: 'allowAlways',
  ClaudePermissionBehavior.denyAlways: 'denyAlways',
};

ClaudeTextBlock _$ClaudeTextBlockFromJson(Map<String, dynamic> json) =>
    ClaudeTextBlock(text: json['text'] as String);

ClaudeThinkingBlock _$ClaudeThinkingBlockFromJson(Map<String, dynamic> json) =>
    ClaudeThinkingBlock(thinking: json['thinking'] as String);

ClaudeToolUseBlock _$ClaudeToolUseBlockFromJson(Map<String, dynamic> json) =>
    ClaudeToolUseBlock(
      id: json['id'] as String,
      name: json['name'] as String,
      input: json['input'] as Map<String, dynamic>,
    );
