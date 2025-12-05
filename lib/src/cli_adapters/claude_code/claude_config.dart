import 'claude_types.dart';

/// Handler type for permission delegation
typedef ClaudePermissionHandler = Future<ClaudeToolPermissionResponse> Function(
  ClaudeToolPermissionRequest request,
);

/// Configuration for a Claude Code session
class ClaudeSessionConfig {
  /// Permission mode for tool execution
  final ClaudePermissionMode permissionMode;

  /// Handler for permission requests when using delegate mode
  final ClaudePermissionHandler? permissionHandler;

  /// Model to use (e.g., 'claude-sonnet-4-5-20250929')
  final String? model;

  /// Custom system prompt (replaces default)
  final String? systemPrompt;

  /// Additional system prompt (appended to default)
  final String? appendSystemPrompt;

  /// Maximum number of turns before stopping
  final int? maxTurns;

  /// List of tools to allow (if specified, only these tools are available)
  final List<String>? allowedTools;

  /// List of tools to disallow
  final List<String>? disallowedTools;

  /// Extra CLI arguments to pass (for testing or advanced use)
  final List<String>? extraArgs;

  ClaudeSessionConfig({
    this.permissionMode = ClaudePermissionMode.defaultMode,
    this.permissionHandler,
    this.model,
    this.systemPrompt,
    this.appendSystemPrompt,
    this.maxTurns,
    this.allowedTools,
    this.disallowedTools,
    this.extraArgs,
  }) {
    if (permissionMode == ClaudePermissionMode.delegate &&
        permissionHandler == null) {
      throw ArgumentError(
        'permissionHandler is required when using delegate permission mode',
      );
    }
  }
}
