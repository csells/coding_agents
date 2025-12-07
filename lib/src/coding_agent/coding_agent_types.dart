/// Token usage statistics for a coding agent turn
class CodingAgentUsage {
  /// Input tokens consumed
  final int inputTokens;

  /// Output tokens generated
  final int outputTokens;

  /// Cached input tokens (if applicable)
  final int? cachedInputTokens;

  /// Cache creation tokens (Claude-specific)
  final int? cacheCreationInputTokens;

  /// Cache read tokens (Claude-specific)
  final int? cacheReadInputTokens;

  /// Total tokens (input + output)
  int get totalTokens => inputTokens + outputTokens;

  CodingAgentUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.cachedInputTokens,
    this.cacheCreationInputTokens,
    this.cacheReadInputTokens,
  });
}

/// Information about a stored coding agent session
class CodingAgentSessionInfo {
  /// Unique session identifier
  final String sessionId;

  /// When the session was created
  final DateTime createdAt;

  /// When the session was last updated
  final DateTime lastUpdatedAt;

  /// Working directory for the session (if available)
  final String? projectDirectory;

  /// Git branch at time of session (if available)
  final String? gitBranch;

  /// Number of messages/turns in the session (if available)
  final int? messageCount;

  CodingAgentSessionInfo({
    required this.sessionId,
    required this.createdAt,
    required this.lastUpdatedAt,
    this.projectDirectory,
    this.gitBranch,
    this.messageCount,
  });
}

/// Status of a completed turn
enum CodingAgentTurnStatus {
  /// Turn completed successfully
  success,

  /// Turn completed with an error
  error,

  /// Turn was cancelled by user
  cancelled,
}

/// Request for tool execution approval
class ToolApprovalRequest {
  /// Unique ID for this approval request
  final String id;

  /// Tool name (e.g., 'bash', 'write', 'read')
  final String toolName;

  /// Human-readable description of the action
  final String description;

  /// Tool input/arguments
  final Map<String, dynamic>? input;

  /// Command to be executed (for shell actions)
  final String? command;

  /// File path (for file operations)
  final String? filePath;

  ToolApprovalRequest({
    required this.id,
    required this.toolName,
    required this.description,
    this.input,
    this.command,
    this.filePath,
  });
}

/// Decision for a tool approval request
enum ToolApprovalDecision {
  /// Allow this specific action
  allow,

  /// Deny this specific action
  deny,

  /// Allow this action and all future similar actions
  allowAlways,

  /// Deny this action and all future similar actions
  denyAlways,
}

/// Response to a tool approval request
class ToolApprovalResponse {
  /// The decision for this approval
  final ToolApprovalDecision decision;

  /// Optional message to include with the response
  final String? message;

  ToolApprovalResponse({required this.decision, this.message});
}

/// Handler for tool execution approval requests
///
/// Called when an agent needs approval for a tool execution.
/// Return a [ToolApprovalResponse] with the decision.
typedef ToolApprovalHandler =
    Future<ToolApprovalResponse> Function(ToolApprovalRequest request);
