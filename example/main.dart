/// coding_agents - Dart adapters for CLI coding agents
///
/// This package provides adapters for interacting with CLI-based coding agents:
/// - Claude Code CLI (claude)
/// - Codex CLI (codex)
/// - Gemini CLI (gemini)
///
/// Each adapter is demonstrated in its own example file:
/// - claude_adapter.dart - Claude Code adapter examples
/// - codex_adapter.dart - Codex adapter examples
/// - gemini_adapter.dart - Gemini adapter examples
///
/// Run individual examples:
///   dart run example/claude_adapter.dart
///   dart run example/codex_adapter.dart
///   dart run example/gemini_adapter.dart
library;

void main(List<String> args) {
  print('coding_agents - Dart adapters for CLI coding agents\n');
  print('Available examples:\n');
  print('  Claude Code adapter:');
  print('    dart run example/claude_adapter.dart\n');
  print('  Codex adapter:');
  print('    dart run example/codex_adapter.dart\n');
  print('  Gemini adapter:');
  print('    dart run example/gemini_adapter.dart\n');
  print('Each example demonstrates:');
  print('  - Creating sessions with configuration');
  print('  - Streaming events from sessions');
  print('  - Multi-turn conversations');
  print('  - Session cancellation\n');

  if (args.isNotEmpty) {
    final adapter = args[0].toLowerCase();
    print('To run the $adapter example:');
    print('  dart run example/${adapter}_adapter.dart');
  }
}
