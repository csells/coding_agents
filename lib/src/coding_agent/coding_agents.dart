// Core interfaces
export 'coding_agent.dart';

// Event types
export 'coding_agent_events.dart';

// Supporting types
export 'coding_agent_types.dart';

// Implementations
export 'claude_coding_agent.dart';
export 'codex_coding_agent.dart';
export 'gemini_coding_agent.dart';

// Re-export adapter types needed for configuration
export '../cli_adapters/claude_code/claude_config.dart'
    show ClaudePermissionHandler;
export '../cli_adapters/claude_code/claude_types.dart'
    show ClaudePermissionMode, ClaudeToolPermissionRequest, ClaudeToolPermissionResponse, ClaudePermissionBehavior;
export '../cli_adapters/codex/codex_types.dart'
    show CodexApprovalPolicy, CodexSandboxMode;
export '../cli_adapters/gemini/gemini_types.dart' show GeminiApprovalMode;
