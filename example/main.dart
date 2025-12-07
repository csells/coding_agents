/// coding_agents - Dart adapters for CLI coding agents
///
/// This package provides adapters for interacting with CLI-based coding agents:
/// - Claude Code CLI
/// - Codex CLI
/// - Gemini CLI
///
/// Examples are organized into two categories:
///
/// 1. API Examples (example/*.dart) - Demonstrate adapter APIs:
///    - claude_code_cli.dart - Claude Code adapter
///    - codex_cli.dart - Codex adapter
///    - gemini_cli.dart - Gemini adapter
///
/// 2. Interactive CLIs (example/simple_cli/*.dart) - Full CLI applications:
///    - claude_cli.dart - Interactive Claude CLI
///    - codex_cli.dart - Interactive Codex CLI
///    - gemini_cli.dart - Interactive Gemini CLI
library;

void main(List<String> args) {
  print('''
coding_agents - Dart adapters for CLI coding agents

Interactive CLIs:
  dart run example/adapter_cli/claude_cli.dart
  dart run example/adapter_cli/codex_cli.dart
  dart run example/adapter_cli/gemini_cli.dart

CLI Options:
  -h, --help               Show help
  -p, --prompt <text>      One-shot prompt
  -l, --list-sessions      List sessions
  -r, --resume-session     Resume session by ID
  -d, --project-directory  Set working directory
  -y, --yolo               Skip approval prompts

REPL Commands:
  /help   Show available commands
  /exit   Exit the REPL
  /quit   Exit the REPL
''');
}
