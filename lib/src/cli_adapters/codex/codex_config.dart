import 'codex_types.dart';

/// Configuration for a Codex CLI session
class CodexSessionConfig {
  /// Approval policy for tool executions
  final CodexApprovalPolicy approvalPolicy;

  /// Sandbox mode for file system access
  final CodexSandboxMode sandboxMode;

  /// Enable full auto mode (no approvals required)
  final bool fullAuto;

  /// Dangerously bypass all approvals and sandbox
  final bool dangerouslyBypassAll;

  /// Model to use (e.g., 'o3', 'o3-mini')
  final String? model;

  /// Enable web search capability
  final bool enableWebSearch;

  /// Environment variables to pass to the process
  final Map<String, String>? environment;

  /// Config overrides (key=value pairs passed via -c flag)
  /// Useful for overriding user config settings
  final List<String>? configOverrides;

  /// Extra CLI arguments to pass (for testing or advanced use)
  final List<String>? extraArgs;

  CodexSessionConfig({
    this.approvalPolicy = CodexApprovalPolicy.onRequest,
    this.sandboxMode = CodexSandboxMode.workspaceWrite,
    this.fullAuto = false,
    this.dangerouslyBypassAll = false,
    this.model,
    this.enableWebSearch = false,
    this.environment,
    this.configOverrides,
    this.extraArgs,
  });
}
