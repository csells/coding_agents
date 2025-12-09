# coding_agents

Dart adapters for CLI-based coding agents: Claude Code, Codex CLI, and Gemini
CLI.

This library provides programmatic control over coding agents through their CLI
interfaces, enabling multi-turn conversations, streaming events, and session
management from Dart applications.

## Features

### Unified CodingAgent Abstraction

A high-level abstraction that provides consistent APIs across all agents:

- **`CodingAgent`**: Factory for creating sessions with agent-specific
  configuration
- **`CodingAgentSession`**: Manages conversation lifecycle with a continuous
  event stream
- **`CodingAgentTurn`**: Represents a single turn with cancellation support
- **Unified events**: `CodingAgentEvent` hierarchy for consistent event handling

### CLI Adapters

Low-level adapters for direct CLI interaction:

- **Claude Code Adapter**: Long-lived bidirectional JSONL sessions with
  streaming events, multi-turn conversations, and session resumption
- **Codex CLI Adapter**: App-server v2 JSON-RPC (`thread/start`, `turn/start`,
  `item/*`) with streaming deltas, approvals, and thread-based session
  management (process-per-turn by default)
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

### Unified CodingAgent (Recommended)

```dart
import 'package:coding_agents/coding_agents.dart';

// Create agent with agent-specific configuration
final agent = ClaudeCodingAgent(
  permissionMode: ClaudePermissionMode.bypassPermissions,
);

// Create a session
final session = await agent.createSession(
  projectDirectory: '/path/to/project',
);

// Subscribe to events (continuous across all turns)
session.events.listen((event) {
  switch (event) {
    case CodingAgentTextEvent():
      print(event.text);
    case CodingAgentToolUseEvent():
      print('Tool: ${event.toolName}');
    case CodingAgentTurnEndEvent():
      print('Turn complete: ${event.status}');
    default:
      break;
  }
});

// Send a message (returns a turn for cancellation)
final turn = await session.sendMessage('Hello!');

// Send another message in the same session
final turn2 = await session.sendMessage('What did I just say?');

// Close when done
await session.close();
```

### Low-Level Claude Code Adapter

```dart
import 'package:coding_agents/coding_agents.dart';

final client = ClaudeCodeCliAdapter();

final config = ClaudeSessionConfig(
  permissionMode: ClaudePermissionMode.bypassPermissions,
  maxTurns: 1,
);

final session = await client.createSession(
  'Hello!',
  config,
  projectDirectory: '/path/to/project',
);
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

final client = CodexCliAdapter();

final config = CodexSessionConfig(fullAuto: true);

final session = await client.createSession(
  'Hello!',
  config,
  projectDirectory: '/path/to/project',
);
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

final client = GeminiCliAdapter();

final config = GeminiSessionConfig(
  approvalMode: GeminiApprovalMode.yolo,
  sandbox: true,
);

final session = await client.createSession(
  'Hello!',
  config,
  projectDirectory: '/path/to/project',
);
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
const projectDir = '/path/to/project';

// First turn
final session1 = await client.createSession(
  'Remember: XYZ',
  config,
  projectDirectory: projectDir,
);
final sessionId = session1.sessionId;
await for (final event in session1.events) {
  if (event is ClaudeResultEvent) break;
}

// Second turn - resume with same session
final session2 = await client.resumeSession(
  sessionId,
  'What did I ask you to remember?',
  config,
  projectDirectory: projectDir,
);
```

### Listing Sessions

All adapters support discovering existing sessions via `listSessions`:

```dart
// List all sessions for a project directory
final sessions = await client.listSessions(
  projectDirectory: '/path/to/project',
);

for (final info in sessions) {
  print('Session: ${info.sessionId}');
  print('  Updated: ${info.lastUpdated}');
}

// Find and resume a specific session
final targetSession = sessions.firstWhere(
  (s) => s.sessionId == storedSessionId,
);
```

### Retrieving Session History

All adapters support fetching the full event history for a session:

```dart
// Get all events from a session (Claude requires projectDirectory)
final history = await client.getSessionHistory(
  sessionId,
  projectDirectory: '/path/to/project',
);

for (final event in history) {
  if (event is ClaudeUserEvent) {
    print('User message');
  } else if (event is ClaudeAssistantEvent) {
    for (final block in event.content) {
      if (block is ClaudeTextBlock) {
        print('Assistant: ${block.text}');
      }
    }
  }
}
```

## Examples

### Unified CLI (Recommended)

The unified CLI (`example/coding_cli.dart`) supports all three agents with an
`--agent` flag:

```bash
# Claude (default)
dart run example/coding_cli.dart -p "What is 2+2?" -y

# Codex
dart run example/coding_cli.dart -a codex -p "What is 2+2?" -y

# Gemini
dart run example/coding_cli.dart -a gemini -p "What is 2+2?" -y
```

**Unified CLI Options:**

| Flag                  | Short | Description                                       |
| --------------------- | ----- | ------------------------------------------------- |
| `--help`              | `-h`  | Show help message                                 |
| `--agent`             | `-a`  | Agent to use: claude, codex, gemini (default: claude) |
| (none)                |       | Interactive multi-turn REPL                       |
| `--project-directory` | `-d`  | Working directory (default: cwd)                  |
| `--prompt`            | `-p`  | Execute a single prompt and exit                  |
| `--list-sessions`     | `-l`  | List sessions with ID, first prompt, last updated |
| `--resume-session`    | `-r`  | Resume a session by ID                            |
| `--yolo`              | `-y`  | Permissive mode (bypass approvals)                |

### Test Script

Run tests against all three agents:

```bash
./example/test_cli_agents.sh
```

The script exercises one-shot prompts, session listing, resume flows, and a
quick REPL exit for Claude, Codex, and Gemini.

### Adapter-Specific CLIs

The `example/adapter_cli/` folder contains CLI wrappers for each low-level
adapter:

```bash
# Claude Code CLI
dart run example/adapter_cli/claude_cli.dart

# Codex CLI
dart run example/adapter_cli/codex_cli.dart

# Gemini CLI
dart run example/adapter_cli/gemini_cli.dart
```

**Usage Examples:**

```bash
# Interactive REPL
dart run example/adapter_cli/claude_cli.dart

# Show help
dart run example/adapter_cli/claude_cli.dart --help

# One-shot prompt
dart run example/adapter_cli/claude_cli.dart -p "What is 2+2?"

# List sessions
dart run example/adapter_cli/claude_cli.dart -l

# Resume session (shows history, then enters REPL)
dart run example/adapter_cli/claude_cli.dart -r <session-id>

# One-shot in resumed session
dart run example/adapter_cli/claude_cli.dart -r <session-id> -p "Continue"

# Different project directory with yolo mode
dart run example/adapter_cli/claude_cli.dart -d /path/to/project -y
```

## Architecture

```
lib/
└── src/
    ├── coding_agent/     # Unified CodingAgent abstraction
    │   ├── coding_agent.dart
    │   ├── coding_agent_events.dart
    │   ├── coding_agent_types.dart
    │   ├── claude_coding_agent.dart
    │   ├── codex_coding_agent.dart
    │   └── gemini_coding_agent.dart
    └── cli_adapters/     # Low-level CLI adapters
        ├── claude_code/
        ├── codex/
        └── gemini/
```

### Unified CodingAgent Pattern

```
CodingAgent
  └── createSession(projectDirectory) → CodingAgentSession
  └── resumeSession(sessionId, projectDirectory) → CodingAgentSession
  └── listSessions(projectDirectory) → List<CodingAgentSessionInfo>

CodingAgentSession
  ├── sessionId: String
  ├── events: Stream<CodingAgentEvent>  # Continuous across turns
  ├── sendMessage(prompt) → CodingAgentTurn
  ├── getHistory() → List<CodingAgentEvent>
  └── close() → void

CodingAgentTurn
  ├── turnId: int
  └── cancel() → void
```

### Low-Level Adapter Pattern

```
Client (per working directory)
  ├── createSession(prompt, config) → Session
  ├── resumeSession(sessionId, prompt, config) → Session
  ├── listSessions() → List<SessionInfo>
  └── getSessionHistory(sessionId) → List<Event>

Session
  ├── sessionId: String
  ├── events: Stream<Event>
  └── cancel() → void
```

## Specifications

- [CLI Streaming Protocol](specs/cli-streaming-protocol.md) - JSONL streaming
  protocols

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
