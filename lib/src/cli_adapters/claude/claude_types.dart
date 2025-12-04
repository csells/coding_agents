import 'package:json_annotation/json_annotation.dart';

part 'claude_types.g.dart';

/// Claude permission modes
enum ClaudePermissionMode {
  /// Prompt for dangerous tools (default behavior)
  defaultMode,

  /// Auto-approve file edits
  acceptEdits,

  /// Skip all permission prompts
  bypassPermissions,

  /// Delegate to permission handler callback
  delegate,
}

/// Permission behavior response values
enum ClaudePermissionBehavior {
  allow,
  deny,
  allowAlways,
  denyAlways,
}

/// Information about a stored Claude session
@JsonSerializable()
class ClaudeSessionInfo {
  final String sessionId;
  final String cwd;
  final String? gitBranch;
  final DateTime timestamp;
  final DateTime lastUpdated;

  ClaudeSessionInfo({
    required this.sessionId,
    required this.cwd,
    this.gitBranch,
    required this.timestamp,
    required this.lastUpdated,
  });

  factory ClaudeSessionInfo.fromJson(Map<String, dynamic> json) =>
      _$ClaudeSessionInfoFromJson(json);
  Map<String, dynamic> toJson() => _$ClaudeSessionInfoToJson(this);
}

/// Tool permission request from Claude
@JsonSerializable()
class ClaudeToolPermissionRequest {
  final String toolName;
  final Map<String, dynamic> toolInput;
  final String sessionId;
  final int turnId;

  ClaudeToolPermissionRequest({
    required this.toolName,
    required this.toolInput,
    required this.sessionId,
    required this.turnId,
  });

  factory ClaudeToolPermissionRequest.fromJson(Map<String, dynamic> json) =>
      _$ClaudeToolPermissionRequestFromJson(json);
  Map<String, dynamic> toJson() => _$ClaudeToolPermissionRequestToJson(this);
}

/// Response to a tool permission request
@JsonSerializable()
class ClaudeToolPermissionResponse {
  final ClaudePermissionBehavior behavior;
  final Map<String, dynamic>? updatedInput;
  final String? message;

  ClaudeToolPermissionResponse({
    required this.behavior,
    this.updatedInput,
    this.message,
  });

  factory ClaudeToolPermissionResponse.fromJson(Map<String, dynamic> json) =>
      _$ClaudeToolPermissionResponseFromJson(json);
  Map<String, dynamic> toJson() => _$ClaudeToolPermissionResponseToJson(this);
}

/// Token usage statistics
class ClaudeUsage {
  final int inputTokens;
  final int outputTokens;
  final int? cacheCreationInputTokens;
  final int? cacheReadInputTokens;

  ClaudeUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheCreationInputTokens,
    this.cacheReadInputTokens,
  });

  /// Parse from JSON, handling both snake_case (Claude API) and camelCase
  factory ClaudeUsage.fromJson(Map<String, dynamic> json) => ClaudeUsage(
        inputTokens:
            (json['input_tokens'] as num?)?.toInt() ??
            (json['inputTokens'] as num?)?.toInt() ??
            0,
        outputTokens:
            (json['output_tokens'] as num?)?.toInt() ??
            (json['outputTokens'] as num?)?.toInt() ??
            0,
        cacheCreationInputTokens:
            (json['cache_creation_input_tokens'] as num?)?.toInt() ??
            (json['cacheCreationInputTokens'] as num?)?.toInt(),
        cacheReadInputTokens:
            (json['cache_read_input_tokens'] as num?)?.toInt() ??
            (json['cacheReadInputTokens'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        if (cacheCreationInputTokens != null)
          'cache_creation_input_tokens': cacheCreationInputTokens,
        if (cacheReadInputTokens != null)
          'cache_read_input_tokens': cacheReadInputTokens,
      };
}

/// Content block in a message
sealed class ClaudeContentBlock {
  const ClaudeContentBlock();

  factory ClaudeContentBlock.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'text' => ClaudeTextBlock.fromJson(json),
      'thinking' => ClaudeThinkingBlock.fromJson(json),
      'tool_use' => ClaudeToolUseBlock.fromJson(json),
      'tool_result' => ClaudeToolResultBlock.fromJson(json),
      _ => ClaudeUnknownBlock(type: type, data: json),
    };
  }
}

@JsonSerializable(createToJson: false)
class ClaudeTextBlock extends ClaudeContentBlock {
  final String text;

  const ClaudeTextBlock({required this.text});

  factory ClaudeTextBlock.fromJson(Map<String, dynamic> json) =>
      _$ClaudeTextBlockFromJson(json);
}

@JsonSerializable(createToJson: false)
class ClaudeThinkingBlock extends ClaudeContentBlock {
  final String thinking;

  const ClaudeThinkingBlock({required this.thinking});

  factory ClaudeThinkingBlock.fromJson(Map<String, dynamic> json) =>
      _$ClaudeThinkingBlockFromJson(json);
}

@JsonSerializable(createToJson: false)
class ClaudeToolUseBlock extends ClaudeContentBlock {
  final String id;
  final String name;
  final Map<String, dynamic> input;

  const ClaudeToolUseBlock({
    required this.id,
    required this.name,
    required this.input,
  });

  factory ClaudeToolUseBlock.fromJson(Map<String, dynamic> json) =>
      _$ClaudeToolUseBlockFromJson(json);
}

class ClaudeToolResultBlock extends ClaudeContentBlock {
  final String toolUseId;
  final String content;
  final bool? isError;

  const ClaudeToolResultBlock({
    required this.toolUseId,
    required this.content,
    this.isError,
  });

  factory ClaudeToolResultBlock.fromJson(Map<String, dynamic> json) =>
      ClaudeToolResultBlock(
        toolUseId: (json['tool_use_id'] ?? json['toolUseId']) as String,
        content: json['content'] as String? ?? '',
        isError: (json['is_error'] ?? json['isError']) as bool?,
      );
}

class ClaudeUnknownBlock extends ClaudeContentBlock {
  final String type;
  final Map<String, dynamic> data;

  const ClaudeUnknownBlock({required this.type, required this.data});
}
