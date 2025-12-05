# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

This is a Dart library (`coding_agents`) that provides adapters for wrapping
CLI-based coding agents (Claude Code, Codex CLI, Gemini CLI). The library
enables programmatic control of these agents via Dart, handling JSONL streaming
over stdio, session management, and multi-turn conversations.

## Build and Development Commands

```bash
# Install dependencies
dart pub get

# Run static analysis
dart analyze

# Run all tests
dart test

# Run a single test file
dart test test/coding_agents_test.dart

# Run example
dart run example/main.dart

# Generate JSON serialization code (after modifying @JsonSerializable classes)
dart run build_runner build
```

## Architecture

### Design Principles (from specs/cli-adapter-design.md)
- **CLI-specific types**: Each adapter (Claude, Codex, Gemini) has its own event
  types, config types, and session types with no shared abstractions
- **Idiomatic Dart**: Use `Stream<T>` for events, `Future<T>` for async
  operations
- **Process management hidden**: Adapters internally manage CLI process
  lifecycle
- **CWD-scoped**: Each client is initialized with a working directory; all
  operations are scoped to that directory
- **Errors as exceptions**: No try-catch wrappers; exceptions propagate to
  consumer

### Directory Structure
```
lib/
└── src/
    └── cli_adapters/
        ├── claude_code/  # Claude Code adapter (long-lived bidirectional JSONL)
        ├── codex/        # Codex CLI adapter (process-per-turn)
        └── gemini/       # Gemini CLI adapter (process-per-turn)
```

### Multi-Turn Architecture Patterns
- **Claude Code**: Long-lived bidirectional JSONL process - send messages via
  stdin
- **Codex CLI**: Process-per-turn - spawn new process with `--resume
  <thread_id>`
- **Gemini CLI**: Process-per-turn - spawn new process with `--resume
  <session_id>`

### Common Adapter Pattern
```dart
Client (per CWD)
  ├── createSession(prompt, config) → Session
  ├── resumeSession(sessionId, prompt, config) → Session
  └── listSessions() → List<SessionInfo>  // Claude only

Session
  ├── sessionId: String (threadId for Codex)
  ├── events: Stream<Event>
  └── cancel() → void
```

## Best Practices

From [specs/best-practices.md](specs/best-practices.md):

- **TDD** - write tests first; implementation isn't done until tests pass
- **DRY** - eliminate duplicated logic by extracting shared utilities
- **Separation of Concerns** - each module handles one distinct responsibility
- **SRP** - every class/module/function/file has exactly one reason to change
- **Clear Abstractions** - expose intent through small, stable interfaces; hide
  implementation details
- **Low Coupling, High Cohesion** - keep modules self-contained, minimize
  cross-dependencies
- **KISS** - keep solutions as simple as possible
- **YAGNI** - avoid speculative complexity or over-engineering
- **Don't Swallow Errors** - no catching exceptions silently, no filling in
  missing values, no adding timeouts when something hangs; throw exceptions so
  root causes can be found
- **No Placeholder Code** - production code only
- **No Comments for Removed Functionality** - source is not for history
- **Layered Architecture** - each layer depends only on the one(s) below it
- **Prefer Non-Nullable Variables** - use nullability sparingly

## Key Specifications

- [specs/cli-adapter-design.md](specs/cli-adapter-design.md): Detailed API
  design for each adapter
- [specs/cli-streaming-protocol.md](specs/cli-streaming-protocol.md): JSONL
  streaming protocols for all three CLIs
- [specs/best-practices.md](specs/best-practices.md): Architectural and coding
  best practices

## Dependencies

- `json_annotation` / `json_serializable`: JSON serialization for event and config types
- `path`: Path manipulation utilities
- Planned: `mcp_dart` for MCP server implementation (Claude permission delegation)

## Coding Agent Protocol

### Clarify Before Starting

If requirements are ambiguous, ask. Thirty seconds of clarification beats an
hour in the wrong direction. Surface assumptions early: "I'm interpreting this
as X—correct?"

### Understand Before Solving

Restate the problem in your own words before writing code. If you can't
articulate what "done" looks like, you're not ready to start.

### Read Before Write

Explore before implementing. Understand the patterns, conventions, and
architecture already in place. Grep for similar code. Check how adjacent
problems were solved. Match the existing style.

### Work Incrementally

Build in small, testable chunks. Get something minimal running, verify it, then
extend. Don't write 400 lines and pray.

### Minimal Diffs

Do what was asked. Resist drive-by refactors, style changes, and "while I'm
here" improvements. Unrelated changes obscure intent and introduce risk.

### Multiple Hypotheses

Never chase your first idea exclusively. Generate 2-3 plausible explanations
before investigating. Actively try to disprove your favorite theory.

### Spike in Isolation

Uncertain how something works? Prototype in a scratch file or test harness
first. Don't experiment on the real codebase.

### Root Cause Over Quick Fix

Patches hide problems. When something breaks, ask "why was this possible?" not
just "how do I make the error go away?"

### Test Your Own Work

Never report success without verification. Run it. See it work. Edge cases too.

### Self-Review Before Done

Read your own diff as a skeptical reviewer. Look for:

- Leftover debug code
- Hardcoded values
- Missing error handling
- Regressions in adjacent functionality

### Learn From Mistakes

When wrong, explicitly state what you believed, what was actually true, and how
your mental model has updated. This compounds into better judgment.

### Failure Triage

Routine failure → investigate independently:

- Form hypothesis, test in isolation
- Try 2-3 approaches before escalating
- Document what you tried

Escalate to Neo when:

- Stuck after genuine investigation
- Root cause implies architectural/requirements issue
- Fix is irreversible or high blast radius
- Ambiguity in what Neo actually wants

### Epistemic Hygiene

- "I believe X" ≠ "I verified X"
- "I don't know" beats confident guessing

### Chesterton's Fence

Can't explain why something exists? Understand before changing. Check git blame.
Grep for references.

### Git Discipline

Atomic commits. Meaningful messages. Never `git add .`

### Handoffs

When stopping: state what's done, what's blocked, what you tried, open
questions, files touched.
