import 'package:json_annotation/json_annotation.dart';

part 'gemini_types.g.dart';

/// Approval mode for Gemini CLI
enum GeminiApprovalMode {
  defaultMode,
  autoEdit,
  yolo,
}

/// Information about a Gemini session
@JsonSerializable()
class GeminiSessionInfo {
  final String sessionId;
  final String projectHash;
  final DateTime startTime;
  final DateTime lastUpdated;
  final int messageCount;

  GeminiSessionInfo({
    required this.sessionId,
    required this.projectHash,
    required this.startTime,
    required this.lastUpdated,
    required this.messageCount,
  });

  factory GeminiSessionInfo.fromJson(Map<String, dynamic> json) =>
      _$GeminiSessionInfoFromJson(json);

  Map<String, dynamic> toJson() => _$GeminiSessionInfoToJson(this);
}

/// Statistics for a Gemini session or turn
class GeminiStats {
  final int totalTokens;
  final int inputTokens;
  final int outputTokens;
  final int durationMs;
  final int toolCalls;

  GeminiStats({
    required this.totalTokens,
    required this.inputTokens,
    required this.outputTokens,
    required this.durationMs,
    required this.toolCalls,
  });

  /// Parse from JSON, handling both camelCase and snake_case, with nullable fields
  factory GeminiStats.fromJson(Map<String, dynamic> json) => GeminiStats(
        totalTokens: (json['totalTokens'] as num?)?.toInt() ??
            (json['total_tokens'] as num?)?.toInt() ??
            0,
        inputTokens: (json['inputTokens'] as num?)?.toInt() ??
            (json['input_tokens'] as num?)?.toInt() ??
            0,
        outputTokens: (json['outputTokens'] as num?)?.toInt() ??
            (json['output_tokens'] as num?)?.toInt() ??
            0,
        durationMs: (json['durationMs'] as num?)?.toInt() ??
            (json['duration_ms'] as num?)?.toInt() ??
            0,
        toolCalls: (json['toolCalls'] as num?)?.toInt() ??
            (json['tool_calls'] as num?)?.toInt() ??
            0,
      );

  Map<String, dynamic> toJson() => {
        'totalTokens': totalTokens,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'durationMs': durationMs,
        'toolCalls': toolCalls,
      };
}

/// Tool use information
@JsonSerializable()
class GeminiToolUse {
  final String toolName;
  final String toolId;
  final Map<String, dynamic> parameters;

  GeminiToolUse({
    required this.toolName,
    required this.toolId,
    required this.parameters,
  });

  factory GeminiToolUse.fromJson(Map<String, dynamic> json) =>
      _$GeminiToolUseFromJson(json);

  Map<String, dynamic> toJson() => _$GeminiToolUseToJson(this);
}

/// Tool result information
@JsonSerializable()
class GeminiToolResult {
  final String toolId;
  final String status;
  final String? output;
  final Map<String, dynamic>? error;

  GeminiToolResult({
    required this.toolId,
    required this.status,
    this.output,
    this.error,
  });

  factory GeminiToolResult.fromJson(Map<String, dynamic> json) =>
      _$GeminiToolResultFromJson(json);

  Map<String, dynamic> toJson() => _$GeminiToolResultToJson(this);
}

/// Response from the GenerateContent API call.
///
/// This is a temporary class that will be replaced by a common API response
/// class.
@JsonSerializable()
class GenerateContentResponse {
  final String? text;
  final String? prompt;
  final GeminiStats stats;
  final List<GeminiToolUse> toolCalls;
  final List<GeminiToolResult> toolResults;
  @JsonKey(includeFromJson: false, includeToJson: false)
  final Stream<GenerateContentResponse> stream;

  GenerateContentResponse({
    this.text,
    this.prompt,
    required this.stats,
    this.toolCalls = const [],
    this.toolResults = const [],
    this.stream = const Stream.empty(),
  });

  factory GenerateContentResponse.fromJson(Map<String, dynamic> json) =>
      _$GenerateContentResponseFromJson(json);

  Map<String, dynamic> toJson() => _$GenerateContentResponseToJson(this);

  GenerateContentResponse copyWith({
    String? text,
    String? prompt,
    GeminiStats? stats,
    List<GeminiToolUse>? toolCalls,
    List<GeminiToolResult>? toolResults,
    Stream<GenerateContentResponse>? stream,
  }) {
    return GenerateContentResponse(
      text: text ?? this.text,
      prompt: prompt ?? this.prompt,
      stats: stats ?? this.stats,
      toolCalls: toolCalls ?? this.toolCalls,
      toolResults: toolResults ?? this.toolResults,
      stream: stream ?? this.stream,
    );
  }
}

/// Configuration for a Gemini CLI session
@JsonSerializable()
class GeminiSessionConfig {
  /// Approval mode for tool executions
  final GeminiApprovalMode approvalMode;

  /// Enable sandbox mode
  final bool sandbox;

  /// Custom sandbox Docker image
  final String? sandboxImage;

  /// Model to use (e.g., 'gemini-2.0-flash-exp')
  final String? model;

  /// Enable debug output
  final bool debug;

  GeminiSessionConfig({
    this.approvalMode = GeminiApprovalMode.defaultMode,
    this.sandbox = false,
    this.sandboxImage,
    this.model,
    this.debug = false,
  });

  factory GeminiSessionConfig.fromJson(Map<String, dynamic> json) =>
      _$GeminiSessionConfigFromJson(json);

  Map<String, dynamic> toJson() => _$GeminiSessionConfigToJson(this);
}

/// The role of the author of a message.
enum ChatRole {
  /// The author is the user.
  user,

  /// The author is the model.
  model,
}

/// A message in a chat conversation.
@JsonSerializable()
class ChatMessage {
  /// The role of the author of this message.
  final ChatRole role;

  /// The content of the message.
  final String text;

  ChatMessage({
    required this.role,
    required this.text,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);

  Map<String, dynamic> toJson() => _$ChatMessageToJson(this);
}

/// Request for a chat completion.
@JsonSerializable()
class ChatRequest {
  /// The messages in the chat conversation.
  final List<ChatMessage> messages;

  /// Configuration for the chat session.
  final GeminiSessionConfig config;

  ChatRequest({
    required this.messages,
    required this.config,
  });

  factory ChatRequest.fromJson(Map<String, dynamic> json) =>
      _$ChatRequestFromJson(json);

  Map<String, dynamic> toJson() => _$ChatRequestToJson(this);
}

