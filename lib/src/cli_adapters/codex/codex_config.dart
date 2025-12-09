import 'codex_types.dart';

/// Handler type for approval requests
///
/// Called when the app-server needs approval for a tool execution.
/// Return a [CodexApprovalResponse] with the decision.
typedef CodexApprovalHandler =
    Future<CodexApprovalResponse> Function(CodexApprovalRequest request);

/// Configuration for a Codex CLI session
class CodexSessionConfig {
  /// Approval policy for tool executions
  ///
  /// - [CodexApprovalPolicy.onRequest]: Prompt for every tool execution
  /// - [CodexApprovalPolicy.untrusted]: Only prompt for untrusted actions
  /// - [CodexApprovalPolicy.onFailure]: Only prompt after failures
  /// - [CodexApprovalPolicy.never]: Never prompt (auto-approve all)
  final CodexApprovalPolicy approvalPolicy;

  /// Sandbox mode for file system access
  final CodexSandboxMode sandboxMode;

  /// Handler for approval requests
  ///
  /// When set, this callback is invoked for each approval request from
  /// the app-server. If not set, the default behavior based on
  /// [approvalPolicy] is used.
  final CodexApprovalHandler? approvalHandler;

  /// Enable full auto mode (no approvals required)
  ///
  /// When true, sets approval policy to [CodexApprovalPolicy.never] and
  /// sandbox mode to [CodexSandboxMode.workspaceWrite].
  final bool fullAuto;

  /// Dangerously bypass all approvals and sandbox
  ///
  /// WARNING: This disables all safety checks. Only use in trusted
  /// environments with full understanding of the risks.
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

  /// Timeout in seconds for RPC initialization calls.
  ///
  /// This timeout applies to JSON-RPC calls during session setup:
  /// - Server initialization
  /// - Conversation/thread creation
  /// - Event subscription
  ///
  /// If the app-server doesn't respond within this time, the process
  /// is killed and a [CodexProcessException] is thrown.
  ///
  /// Defaults to 15 seconds. Increase if running on slow systems
  /// or with high latency.
  final int rpcTimeoutSeconds;

  CodexSessionConfig({
    this.approvalPolicy = CodexApprovalPolicy.onRequest,
    this.sandboxMode = CodexSandboxMode.workspaceWrite,
    this.approvalHandler,
    this.fullAuto = false,
    this.dangerouslyBypassAll = false,
    this.model,
    this.enableWebSearch = false,
    this.environment,
    this.configOverrides,
    this.extraArgs,
    this.rpcTimeoutSeconds = 15,
  });
}
