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
