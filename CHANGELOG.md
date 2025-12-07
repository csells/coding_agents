## 0.3.0

- Added unified `CodingAgent` abstraction layer with agent-specific
  implementations (`ClaudeCodingAgent`, `CodexCodingAgent`, `GeminiCodingAgent`)
- Unified event types (`CodingAgentEvent` hierarchy) for consistent event
  handling across all adapters
- New session lifecycle: `createSession()` → `sendMessage()` → events flow →
  `close()`
- Added `CodingAgentTurn` for turn-level control with `cancel()` support
- Added `getHistory()` on sessions for retrieving conversation history
- Added unified CLI example (`example/coding_cli.dart`) with `--agent` flag to
  switch between Claude, Codex, and Gemini
- Added test script (`example/test_cli_agents.sh`) for all three agents
- Added `ClaudeToolProgressEvent` and `ClaudeAuthStatusEvent` to Claude adapter
  for spec compliance

## 0.2.0

- Added interactive CLI examples for all three adapters (Claude, Codex, Gemini)
- Changed from `cwd` constructor parameter to `projectDirectory` on method calls
- Added `getSessionHistory()` method to all adapters for retrieving conversation
  history
- Examples demonstrate session creation, resumption, listing, and cancellation

## 0.1.0

- Initial version.
