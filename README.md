# coding_agents

Dart adapters for CLI-based coding agents: Claude Code, Codex CLI, and Gemini CLI.

This library provides programmatic control over coding agents through their CLI
interfaces, enabling multi-turn conversations, streaming events, and session
management from Dart applications.

## Features

- **Claude Code Adapter**: Long-lived bidirectional JSONL sessions with streaming
  events, multi-turn conversations, and session resumption
- **Codex CLI Adapter**: Process-per-turn model with thread-based session
  management and full-auto mode support
- **Gemini CLI Adapter**: Process-per-turn model with sandbox mode and session
  resumption via UUID

Each adapter provides:
- Session creation and resumption
- Streaming events (messages, tool calls, results)
- Configuration options (models, approval modes, sandbox)
- Session listing and management

## Prerequisites

Install the CLI tools you plan to use:

- **Claude Code**: `npm install -g @anthropic-ai/claude-code`
- **Codex CLI**: `npm install -g @openai/codex`
- **Gemini CLI**: `npm install -g @google/gemini-cli`

## Getting Started

Add to your `pubspec.yaml`:

```yaml
dependencies:
  coding_agents:
    path: /path/to/coding_agents
```

## Usage

### Claude Code Adapter

```dart
import 'package:coding_agents/coding_agents.dart';

final client = ClaudeCodeCliAdapter(cwd: '/path/to/project');

final config = ClaudeSessionConfig(
  permissionMode: ClaudePermissionMode.bypassPermissions,
  maxTurns: 1,
);

final session = await client.createSession('Hello!', config);
print('Session ID: ${session.sessionId}');

await for (final event in session.events) {
  if (event is ClaudeAssistantEvent) {
    for (final block in event.content) {
      if (block is ClaudeTextBlock) {
        print('Claude: ${block.text}');
      }
    }
  }
  if (event is ClaudeResultEvent) break;
}
```

### Codex CLI Adapter

```dart
import 'package:coding_agents/coding_agents.dart';

final client = CodexCliAdapter(cwd: '/path/to/project');

final config = CodexSessionConfig(fullAuto: true);

final session = await client.createSession('Hello!', config);
print('Thread ID: ${session.threadId}');

await for (final event in session.events) {
  if (event is CodexAgentMessageEvent) {
    print('Codex: ${event.text}');
  }
  if (event is CodexTurnCompletedEvent) break;
}
```

### Gemini CLI Adapter

```dart
import 'package:coding_agents/coding_agents.dart';

final client = GeminiCliAdapter(cwd: '/path/to/project');

final config = GeminiSessionConfig(
  approvalMode: GeminiApprovalMode.yolo,
  sandbox: true,
);

final session = await client.createSession('Hello!', config);
print('Session ID: ${session.sessionId}');

await for (final event in session.events) {
  if (event is GeminiMessageEvent && event.role == 'assistant') {
    print('Gemini: ${event.content}');
  }
  if (event is GeminiResultEvent) break;
}
```

### Multi-Turn Conversations

All adapters support multi-turn conversations via `resumeSession`:

```dart
// First turn
final session1 = await client.createSession('Remember: XYZ', config);
final sessionId = session1.sessionId;
await for (final event in session1.events) {
  if (event is ClaudeResultEvent) break;
}

// Second turn - resume with same session
final session2 = await client.resumeSession(
  sessionId,
  'What did I ask you to remember?',
  config,
);
```

### Listing Sessions

All adapters support discovering existing sessions via `listSessions`:

```dart
// List all sessions for this working directory
final sessions = await client.listSessions();

for (final info in sessions) {
  print('Session: ${info.sessionId}');
  print('  Updated: ${info.lastUpdated}');
}

// Find and resume a specific session
final targetSession = sessions.firstWhere(
  (s) => s.sessionId == storedSessionId,
);
```

## Examples

See the `example/` folder for complete examples:

```bash
dart run example/claude_code_cli.dart
dart run example/codex_cli.dart
dart run example/gemini_cli.dart
```

## Architecture

```
lib/
└── src/
    └── cli_adapters/
        ├── claude_code/  # Claude Code adapter
        ├── codex/        # Codex CLI adapter
        └── gemini/       # Gemini CLI adapter
```

Each adapter follows the pattern:

```
Client (per working directory)
  ├── createSession(prompt, config) → Session
  ├── resumeSession(sessionId, prompt, config) → Session
  └── listSessions() → List<SessionInfo>

Session
  ├── sessionId: String
  ├── events: Stream<Event>
  └── cancel() → void
```

## Specifications

- [CLI Adapter Design](specs/cli-adapter-design.md) - Detailed API design
- [CLI Streaming Protocol](specs/cli-streaming-protocol.md) - JSONL streaming protocols
- [Best Practices](specs/best-practices.md) - Coding guidelines

## Development

```bash
# Install dependencies
dart pub get

# Run tests
dart test

# Run analyzer
dart analyze

# Generate JSON serialization code
dart run build_runner build
```

## License

See LICENSE file.
