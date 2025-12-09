# CLI Agent Streaming Protocol Specification

Comprehensive specification of headless stdio/JSONL streaming protocols for
Claude Code, Codex CLI, and Gemini CLI with a unified abstraction layer for Dart
client library implementation.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Transport Layer](#2-transport-layer)
3. [Claude Code Protocol](#3-claude-code-protocol)
4. [Codex CLI Protocol](#4-codex-cli-protocol)
5. [Gemini CLI Protocol](#5-gemini-cli-protocol)
6. [Semantic Comparison](#6-semantic-comparison)
7. [Unified Protocol Specification](#7-unified-protocol-specification)
8. [JSON Schema Definitions](#8-json-schema-definitions)
9. [Implementation Notes](#9-implementation-notes)

---

## 1. Executive Summary

All three major AI coding CLI agents support **headless operation via stdio with
JSONL (newline-delimited JSON) streaming output**. This specification documents
the native streaming protocols.

| CLI             | Headless Command      | Output Flag                   | Message Format |
| --------------- | --------------------- | ----------------------------- | -------------- |
| **Claude Code** | `claude -p "prompt"`  | `--output-format stream-json` | JSONL          |
| **Codex CLI**   | `codex "prompt"`      | `--json`                      | JSONL          |
| **Gemini CLI**  | `gemini -p "prompt"`  | `--output-format stream-json` | JSONL          |

### Multi-Turn Architecture Comparison

All three CLIs support **multi-turn conversations with session persistence**,
but use different architectural patterns:

| CLI             | Process Model                         | Session Persistence | Multi-Turn Pattern                             | Session Storage                  |
| --------------- | ------------------------------------- | ------------------- | ---------------------------------------------- | -------------------------------- |
| **Claude Code** | Long-lived (bidirectional JSONL)      | Disk                | Send messages to same process via stdin        | `~/.claude/sessions/`            |
| **Codex CLI**   | App-server JSON-RPC (v2 thread/turn/items); CLI usually exits after each turn | Disk | JSON-RPC turn/start per process; threads can be resumed | `~/.codex/sessions/`             |
| **Gemini CLI**  | Process-per-turn                      | Disk                | Spawn new process with `--resume <session_id>` | `~/.gemini/tmp/<project>/chats/` |

**Key insight:** Claude Code and Codex app-server both support **long-lived
bidirectional communication** within a single process. Codex uses JSON-RPC over
stdio for IDE integration. Gemini uses a process-per-turn model with disk-based
session restoration.

### Common Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Client Application                        │
├─────────────────────────────────────────────────────────────────┤
│  spawn process  │  write stdin  │  read stdout  │  parse JSONL  │
└────────┬────────┴───────┬───────┴───────┬───────┴───────┬───────┘
         │                │               │               │
         ▼                ▼               ▼               ▼
┌─────────────────────────────────────────────────────────────────┐
│                     CLI Process (stdio)                          │
│  claude / codex / gemini                                        │
├─────────────────────────────────────────────────────────────────┤
│  stdin: prompt/input  │  stdout: JSONL events  │  stderr: logs  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Transport Layer

### 2.1 Unified Transport: Stdio with JSONL

All three CLIs use the same fundamental transport mechanism:

- **Process spawning:** Client spawns CLI as subprocess
- **Input:** Prompt via command-line argument or stdin pipe
- **Output:** JSONL events streamed to stdout (one JSON object per line)
- **Errors/Logs:** Human-readable output to stderr
- **Termination:** Process exit signals completion

### 2.2 JSONL Format

Each line of output is a complete, self-contained JSON object:

```
{"type":"event_type","field1":"value1","field2":"value2"}\n
{"type":"event_type","field1":"value1","field2":"value2"}\n
```

**Parsing rules:**
- Split on newline (`\n`)
- Parse each line as independent JSON
- Empty lines should be ignored
- Lines starting with non-`{` characters may be stderr leakage (ignore or log)

### 2.3 Process Lifecycle

```
1. Client spawns CLI process with arguments
2. CLI initializes, emits init/start event
3. CLI processes prompt, streams events
4. CLI completes, emits result/end event
5. Process exits with status code (0 = success)
```

---

## 3. Claude Code Protocol

### 3.1 Invocation

**Basic headless execution:**
```bash
claude -p "Your prompt here" --output-format stream-json
```

**With piped input:**
```bash
cat file.txt | claude -p "Analyze this" --output-format stream-json
```

**Resume session:**
```bash
claude -p "Continue" --output-format stream-json --resume <session-id>
claude -c --output-format stream-json  # Resume most recent
```

**Full streaming with partial messages:**
```bash
claude -p "prompt" --output-format stream-json --include-partial-messages
```

### 3.2 CLI Arguments

| Argument                          | Short | Description                      |
| --------------------------------- | ----- | -------------------------------- |
| `--print`                         | `-p`  | Non-interactive/headless mode    |
| `--output-format <fmt>`           |       | `text`, `json`, or `stream-json` |
| `--input-format <fmt>`            |       | `text` or `stream-json`          |
| `--include-partial-messages`      |       | Include streaming deltas         |
| `--continue`                      | `-c`  | Resume most recent session       |
| `--resume <id>`                   | `-r`  | Resume specific session          |
| `--dangerously-skip-permissions`  |       | Auto-approve all tools (YOLO)    |
| `--allowedTools <list>`           |       | Tools to auto-approve            |
| `--disallowedTools <list>`        |       | Tools to block                   |
| `--permission-mode <mode>`        |       | Permission mode (e.g., `plan`)   |
| `--permission-prompt-tool <tool>` |       | MCP tool for permission prompts  |
| `--max-turns <n>`                 |       | Limit agentic turns              |
| `--model <model>`                 |       | Model selection                  |
| `--system-prompt <text>`          |       | Replace system prompt            |
| `--append-system-prompt <text>`   |       | Add to system prompt             |
| `--verbose`                       |       | Detailed turn-by-turn output     |
| `--json-schema <schema>`          |       | Validate output against schema   |

### 3.3 Input Format (stdin)

Claude Code supports **continuous JSONL streaming** via stdin when using
`--input-format stream-json`. This enables true multi-turn conversations within
a single process.

**Invocation for continuous streaming:**
```bash
claude --output-format stream-json --input-format stream-json
```

**Input Message Schema:**

User message (send follow-up prompts):
```json
{"type":"message","role":"user","content":[{"type":"text","text":"Your follow-up message here"}]}
```

The input format mirrors the output message format. Each line must be a complete
JSON object.

**Multi-turn Flow:**
1. Spawn process with `--output-format stream-json --input-format stream-json`
2. Write initial prompt as JSONL to stdin
3. Read JSONL events from stdout (init, message, tool_use, tool_result, etc.)
4. When assistant completes a response, write next user message to stdin
5. Continue until session ends or process is terminated

**Input Message Types:**

| Type      | Purpose        | Schema                                                                      |
| --------- | -------------- | --------------------------------------------------------------------------- |
| `message` | User follow-up | `{"type":"message","role":"user","content":[{"type":"text","text":"..."}]}` |

**Note:** Unlike Codex and Gemini CLIs, Claude Code maintains a persistent
connection. Do NOT close stdin after the initial prompt if you intend to send
follow-up messages.

### 3.4 Event Types

```typescript
type ClaudeStreamEventType =
  | "user"           // User message (input to the model)
  | "assistant"      // Assistant message (model output)
  | "tool_use"       // Tool invocation request
  | "tool_result"    // Tool execution result
  | "tool_progress"  // Real-time tool execution progress
  | "result"         // Session completion status
  | "error"          // Error occurred
  | "system"         // System event (multiple subtypes)
  | "stream_event"   // Raw API streaming delta (with includePartialMessages)
  | "auth_status"    // Authentication state updates

// System event subtypes
type ClaudeSystemSubtype =
  | "init"             // System initialization info
  | "compact_boundary" // Context compaction marker
  | "status"           // Status updates (e.g., compacting)
  | "hook_response"    // Hook callback responses

// Message content block types
type ClaudeContentBlockType =
  | "text"      // Plain text content
  | "tool_use"  // Inline tool use reference

// Result status values (via subtype field)
type ClaudeResultSubtype =
  | "success"                        // Completed successfully
  | "error_during_execution"         // Error during execution
  | "error_max_turns"                // Max turns limit reached
  | "error_max_budget_usd"           // Budget limit reached
  | "error_max_structured_output_retries" // Structured output retries exceeded

// Assistant message error types
type ClaudeAssistantErrorType =
  | "authentication_failed"
  | "billing_error"
  | "rate_limit"
  | "invalid_request"
  | "server_error"
  | "unknown"
```

### 3.5 Event Schemas

All events include `uuid` and `session_id` fields for correlation.

#### System Event (Init Subtype)
The first event emitted when a session starts:
```json
{
  "type": "system",
  "subtype": "init",
  "uuid": "550e8400-e29b-41d4-a716-446655440000",
  "session_id": "sess_abc123",
  "agents": ["agent1", "agent2"],
  "apiKeySource": "user",
  "betas": ["context-1m-2025-08-07"],
  "claude_code_version": "1.0.32",
  "cwd": "/path/to/project",
  "tools": ["Read", "Edit", "Write", "Bash", "Glob", "Grep"],
  "mcp_servers": [{"name": "server1", "status": "connected"}],
  "model": "claude-sonnet-4-20250514",
  "permissionMode": "default",
  "slash_commands": ["/help", "/clear"],
  "output_style": "text",
  "skills": [],
  "plugins": [{"name": "plugin1", "path": "/path/to/plugin"}]
}
```

**apiKeySource values:** `user`, `project`, `org`, `temporary`

**permissionMode values:** `default`, `acceptEdits`, `bypassPermissions`, `plan`, `dontAsk`

#### User Event
User messages sent to the model:
```json
{
  "type": "user",
  "uuid": "550e8400-e29b-41d4-a716-446655440001",
  "session_id": "sess_abc123",
  "message": {
    "role": "user",
    "content": [{"type": "text", "text": "Refactor the auth module"}]
  },
  "parent_tool_use_id": null,
  "isSynthetic": false,
  "tool_use_result": null
}
```

#### User Event (Replay)
Acknowledgment of previously added user messages:
```json
{
  "type": "user",
  "uuid": "550e8400-e29b-41d4-a716-446655440002",
  "session_id": "sess_abc123",
  "message": {...},
  "parent_tool_use_id": null,
  "isReplay": true
}
```

#### Assistant Event
Assistant responses from the model:
```json
{
  "type": "assistant",
  "uuid": "550e8400-e29b-41d4-a716-446655440003",
  "session_id": "sess_abc123",
  "message": {
    "role": "assistant",
    "content": [
      {"type": "text", "text": "I'll help you refactor the authentication module..."}
    ]
  },
  "parent_tool_use_id": null,
  "error": null
}
```

When an error occurs during model response:
```json
{
  "type": "assistant",
  "uuid": "...",
  "session_id": "...",
  "message": {...},
  "parent_tool_use_id": null,
  "error": "rate_limit"
}
```

#### Tool Use Event
Tool invocation request (embedded in assistant message content):
```json
{
  "type": "tool_use",
  "id": "toolu_01ABC123",
  "name": "Edit",
  "input": {
    "file_path": "/src/auth.ts",
    "old_string": "function login()",
    "new_string": "async function login()"
  }
}
```

#### Tool Result Event
Tool execution result (embedded in user message as tool_use_result):
```json
{
  "type": "tool_result",
  "tool_use_id": "toolu_01ABC123",
  "content": "File updated successfully",
  "is_error": false
}
```

#### Tool Progress Event
Real-time progress updates during tool execution:
```json
{
  "type": "tool_progress",
  "uuid": "550e8400-e29b-41d4-a716-446655440004",
  "session_id": "sess_abc123",
  "tool_use_id": "toolu_01ABC123",
  "tool_name": "Bash",
  "parent_tool_use_id": null,
  "elapsed_time_seconds": 5.2
}
```

#### Result Event (Success)
```json
{
  "type": "result",
  "subtype": "success",
  "uuid": "550e8400-e29b-41d4-a716-446655440005",
  "session_id": "sess_abc123",
  "duration_ms": 12500,
  "duration_api_ms": 10200,
  "is_error": false,
  "num_turns": 3,
  "result": "Done! I've refactored the auth module.",
  "total_cost_usd": 0.0125,
  "usage": {
    "input_tokens": 5000,
    "output_tokens": 1200,
    "cache_read_input_tokens": 2000,
    "cache_creation_input_tokens": 500,
    "web_search_requests": 0,
    "costUSD": 0.0125,
    "contextWindow": 200000
  },
  "modelUsage": {
    "claude-sonnet-4-20250514": {
      "inputTokens": 5000,
      "outputTokens": 1200,
      "cacheReadInputTokens": 2000,
      "cacheCreationInputTokens": 500,
      "webSearchRequests": 0,
      "costUSD": 0.0125,
      "contextWindow": 200000
    }
  },
  "permission_denials": [],
  "structured_output": null
}
```

#### Result Event (Error)
```json
{
  "type": "result",
  "subtype": "error_during_execution",
  "uuid": "...",
  "session_id": "sess_abc123",
  "duration_ms": 5000,
  "duration_api_ms": 4500,
  "is_error": true,
  "num_turns": 2,
  "total_cost_usd": 0.005,
  "usage": {...},
  "modelUsage": {...},
  "permission_denials": [
    {
      "tool_name": "Bash",
      "tool_use_id": "toolu_01XYZ",
      "tool_input": {"command": "rm -rf /"}
    }
  ],
  "errors": ["Tool execution blocked by user"]
}
```

#### Error Event
```json
{
  "type": "error",
  "error": {
    "type": "permission_denied",
    "message": "Tool execution blocked by user"
  }
}
```

#### System Event (Compact Boundary Subtype)
Emitted when conversation context is compacted:
```json
{
  "type": "system",
  "subtype": "compact_boundary",
  "uuid": "...",
  "session_id": "sess_abc123",
  "compact_metadata": {
    "trigger": "auto",
    "pre_tokens": 50000
  }
}
```

**trigger values:** `auto`, `manual`

#### System Event (Status Subtype)
Status updates during processing:
```json
{
  "type": "system",
  "subtype": "status",
  "uuid": "...",
  "session_id": "sess_abc123",
  "status": "compacting"
}
```

#### System Event (Hook Response Subtype)
Hook callback execution responses:
```json
{
  "type": "system",
  "subtype": "hook_response",
  "uuid": "...",
  "session_id": "sess_abc123",
  "hook_name": "PreToolUse",
  "hook_event": "Edit",
  "stdout": "Hook output...",
  "stderr": "",
  "exit_code": 0
}
```

#### Stream Event (Partial Messages)
When `includePartialMessages` is enabled, raw API streaming deltas are exposed:
```json
{
  "type": "stream_event",
  "uuid": "...",
  "session_id": "sess_abc123",
  "event": {
    "type": "content_block_delta",
    "index": 0,
    "delta": {"type": "text_delta", "text": "I'll"}
  },
  "parent_tool_use_id": null
}
```

#### Auth Status Event
Authentication state updates:
```json
{
  "type": "auth_status",
  "uuid": "...",
  "session_id": "sess_abc123",
  "isAuthenticating": true,
  "output": ["Authenticating with API key..."],
  "error": null
}
```

### 3.6 Complete Event Flow Example

```jsonl
{"type":"system","subtype":"init","uuid":"uuid1","session_id":"sess_abc123","claude_code_version":"1.0.32","cwd":"/project","tools":["Read","Edit"],"model":"claude-sonnet-4-20250514","permissionMode":"default"}
{"type":"user","uuid":"uuid2","session_id":"sess_abc123","message":{"role":"user","content":[{"type":"text","text":"Refactor the auth module"}]},"parent_tool_use_id":null}
{"type":"assistant","uuid":"uuid3","session_id":"sess_abc123","message":{"role":"assistant","content":[{"type":"text","text":"I'll analyze the codebase..."},{"type":"tool_use","id":"toolu_01","name":"Read","input":{"file_path":"/src/auth.ts"}}]},"parent_tool_use_id":null}
{"type":"user","uuid":"uuid4","session_id":"sess_abc123","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_01","content":"export function login()..."}]},"parent_tool_use_id":"toolu_01","isSynthetic":true}
{"type":"assistant","uuid":"uuid5","session_id":"sess_abc123","message":{"role":"assistant","content":[{"type":"text","text":"I found the auth module. Let me refactor it..."},{"type":"tool_use","id":"toolu_02","name":"Edit","input":{"file_path":"/src/auth.ts","old_string":"function login()","new_string":"async function login()"}}]},"parent_tool_use_id":null}
{"type":"tool_progress","uuid":"uuid6","session_id":"sess_abc123","tool_use_id":"toolu_02","tool_name":"Edit","elapsed_time_seconds":0.5}
{"type":"user","uuid":"uuid7","session_id":"sess_abc123","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_02","content":"File updated"}]},"parent_tool_use_id":"toolu_02","isSynthetic":true}
{"type":"assistant","uuid":"uuid8","session_id":"sess_abc123","message":{"role":"assistant","content":[{"type":"text","text":"Done! I've made the login function async."}]},"parent_tool_use_id":null}
{"type":"result","subtype":"success","uuid":"uuid9","session_id":"sess_abc123","duration_ms":12500,"is_error":false,"num_turns":3,"result":"Done!","usage":{"input_tokens":5000,"output_tokens":1200}}
```

### 3.7 Permission Control

| Mode           | Flag / SDK Option                 | Behavior                    |
| -------------- | --------------------------------- | --------------------------- |
| Default        | `permissionMode: "default"`       | Prompt for each tool        |
| Accept Edits   | `permissionMode: "acceptEdits"`   | Auto-approve file edits     |
| Bypass All     | `permissionMode: "bypassPermissions"` | Auto-approve all (YOLO) |
| Plan mode      | `permissionMode: "plan"`          | Planning only, no execution |
| Don't Ask      | `permissionMode: "dontAsk"`       | Deny if not pre-approved    |
| CLI YOLO       | `--dangerously-skip-permissions`  | Auto-approve all            |
| Allowlist      | `--allowedTools "Read,Edit"`      | Auto-approve listed tools   |
| Blocklist      | `--disallowedTools "Bash"`        | Block listed tools          |
| MCP Delegate   | `--permission-prompt-tool <tool>` | Delegate to MCP tool        |

**Tool format examples:**
```bash
--allowedTools "Bash(git log:*)" "Bash(git diff:*)" "Read" "Edit"
```

**SDK canUseTool callback:**
```typescript
canUseTool: async (toolName, input, options) => {
  // Return permission decision
  return { behavior: 'allow' };
  // Or with updated input
  return { behavior: 'allow', updatedInput: {...} };
  // Or deny
  return { behavior: 'deny', message: 'Reason for denial' };
}
```

### 3.8 Permission Prompt Tool (MCP Delegation)

For headless orchestration, Claude Code supports delegating permission prompts
to an external MCP tool via `--permission-prompt-tool
<mcp_server_name>__<tool_name>`.

**Invocation:**
```bash
claude -p "refactor the code" \
  --output-format stream-json \
  --permission-prompt-tool my_server__permission_handler
```

**How it works:**
1. When Claude Code needs permission for a tool, it calls the specified MCP tool
2. The MCP tool receives the permission request as its input
3. The MCP tool returns a decision (allow/deny)
4. Claude Code proceeds based on the decision

**Permission Request Input (sent to MCP tool):**
```json
{
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "/src/auth.ts",
    "old_string": "function login()",
    "new_string": "async function login()"
  },
  "context": {
    "session_id": "sess_abc123",
    "turn_number": 3,
    "working_directory": "/path/to/project"
  }
}
```

**Permission Response (returned from MCP tool):**

Allow the tool execution:
```json
{
  "behavior": "allow"
}
```

Allow with modified input:
```json
{
  "behavior": "allow",
  "updatedInput": {
    "file_path": "/src/auth.ts",
    "old_string": "function login()",
    "new_string": "async function login(): Promise<void>"
  }
}
```

Deny the tool execution:
```json
{
  "behavior": "deny",
  "message": "User policy denies file modifications outside /src directory"
}
```

**Behavior values:** | Value | Description | |-------|-------------| | `"allow"`
| Permit the tool execution | | `"deny"` | Block the tool execution | |
`"allowAlways"` | Allow this tool for remainder of session | | `"denyAlways"` |
Deny this tool for remainder of session |

**Note:** When using `--permission-prompt-tool`, no permission events are
emitted in the stream. The permission flow is handled entirely through the MCP
tool call mechanism. The orchestrating client must implement the MCP server with
the permission handling tool.

### 3.9 Session Management

**List sessions:**
```bash
claude --list-sessions
```

**Resume by ID:**
```bash
claude -p "continue" --resume sess_abc123
```

**Resume most recent:**
```bash
claude -c -p "continue"
```

**Session storage location:**
```
~/.claude/sessions/
```

**SDK Session Options:**
```typescript
{
  resume: "sess_abc123",           // Resume by session ID
  resumeSessionAt: "uuid-of-msg",  // Resume at specific message UUID
  continue: true,                  // Continue most recent session
  forkSession: true,               // Fork to new session when resuming
}
```

**V2 Unstable API (SDK):**
```typescript
// Create a persistent session
const session = await claude.unstable_v2_createSession(options);

// Resume an existing session
const session = await claude.unstable_v2_resumeSession(sessionId, options);

// One-shot convenience function
const result = await claude.unstable_v2_prompt(prompt, options);
```

**Query Control Methods (SDK):**
```typescript
const query = claude.query(options);
query.interrupt();                    // Stop processing
query.setPermissionMode(mode);        // Change permission mode
query.setModel(model);                // Change model
query.setMaxThinkingTokens(tokens);   // Set thinking token limit
query.supportedCommands();            // Get available slash commands
query.supportedModels();              // Get available models
query.mcpServerStatus();              // Get MCP server status
query.accountInfo();                  // Get authenticated account info
```

---

## 4. Codex CLI Protocol

### 4.1 Execution Modes

Codex CLI supports two execution modes:

1. **App-Server Mode (v2 JSON-RPC, default since 0.44.x):** JSON-RPC over
   stdio using `thread/start`, `turn/start`, and `item/*` notifications.
   Approvals arrive as JSON-RPC requests. The protocol is single-process
   capable; the shipping CLI typically runs one turn then exits.

2. **Exec Mode** (legacy): Process-per-turn with JSONL streaming output,
   auto-approval only.

### 4.2 App-Server Mode (Recommended)

The app-server provides a JSON-RPC interface over stdio for IDE integration and
programmatic access.

- **Current v2 protocol (CLI ≥ 0.44.x):** `initialize` → `thread/start` /
  `thread/resume` → `turn/start` → streaming notifications (`thread/started`,
  `turn/started`, `item/agentMessage/delta`, `item/reasoning/textDelta`,
  `item/started`, `item/completed`, `turn/completed`). Approval requests arrive
  as JSON-RPC calls such as `item/commandExecution/requestApproval` and
  `item/fileChange/requestApproval`. Token usage may still surface as
  `codex/event/token_count` notifications for compatibility.
- **Legacy v1 RPCs:** `newConversation` / `resumeConversation` /
  `addConversationListener` / `sendUserMessage` (and the even older
  `createThread` / `resumeThread` / `createTurn`) belong to the earlier JSONL
  flow. They remain useful when parsing archived session logs but are not used
  by the v2 adapter.

**Starting the app-server:**
```bash
codex app-server [options]
```

**App-Server Arguments:**

| Argument                                   | Short | Description                       |
| ------------------------------------------ | ----- | --------------------------------- |
| `--full-auto`                              |       | Auto-approve with workspace sandbox |
| `--dangerously-bypass-approvals-and-sandbox` | `--yolo` | Full access, no sandboxing    |
| `--model <name>`                           | `-m`  | Model selection                   |
| `-a <policy>`                              |       | Approval policy                   |
| `-s <mode>`                                |       | Sandbox mode                      |
| `--search`                                 |       | Enable web search                 |
| `-c <key=value>`                           |       | Config overrides                  |

#### Current JSON-RPC Methods (CLI ≥ 0.44.x)

| Method            | Description                          | Parameters (camelCase)                                        |
| ----------------- | ------------------------------------ | ------------------------------------------------------------- |
| `initialize`      | Identify client                      | `clientInfo { name, version }`                                |
| `thread/start`    | Create a new thread                  | `model?`, `modelProvider?`, `cwd?`, `approvalPolicy?`, `sandbox?`, `config?`, `baseInstructions?`, `developerInstructions?` |
| `thread/resume`   | Resume a saved thread                | `threadId`, optional overrides (same shape as `thread/start`) |
| `turn/start`      | Start a turn on a thread             | `threadId`, `input: [UserInput]`, optional overrides (`cwd`, `approvalPolicy`, `sandboxPolicy`, `model`, `effort`, `summary`) |
| `turn/interrupt`  | Interrupt current turn               | `threadId`, `turnId`                                          |
| `thread/list`     | List recorded threads                | `cursor?`, `limit?`, `modelProviders?`                        |
| `thread/archive`  | Archive a thread                     | `threadId`                                                    |
| `review/start`    | Start a review                       | `threadId`, `target`, optional `delivery`                     |

**Adapter note:** The Dart Codex adapter uses this v2 surface by default,
streaming `item/agentMessage/delta` as partial text, and still understands
legacy `codex/event/*` and stored JSONL history when resuming old sessions.

**Key Notifications (v2, method field):**
- `thread/started` (params.thread.id)
- `turn/started`
- `turn/completed`
- `item/started`, `item/completed`
- `item/agentMessage/delta`, `item/reasoning/textDelta`, etc.
- `turn/plan/updated`, `turn/diff/updated`
- Approval requests arrive as JSON-RPC requests:
  - `item/commandExecution/requestApproval`
  - `item/fileChange/requestApproval`

**User input shape (v2):**
```json
{ "type": "text", "text": "hello" }
{ "type": "image", "url": "https://..." }
{ "type": "localImage", "path": "/abs/path.png" }
```

**Approval Handling:**

When approval is required, the server emits an `approval.required` event and
waits for the client to respond:

```json
// Server notification
{"type":"approval.required","id":"approval_1","turn_id":"turn_1","action_type":"shell","description":"Run: npm test","command":"npm test","tool_name":"bash","tool_input":{"command":"npm test"},"file_path":null}

// Client response
{"jsonrpc":"2.0","id":3,"method":"respondToApproval","params":{"approval_id":"approval_1","decision":"allow"}}

// Client response with message (for deny)
{"jsonrpc":"2.0","id":4,"method":"respondToApproval","params":{"approval_id":"approval_2","decision":"deny","message":"Reason for denial"}}
```

**Decision values:** `allow`, `deny`, `allow_always`, `deny_always`

**Config Override Syntax (`-c`):**

The `-c` flag accepts key=value pairs to override config settings:
```bash
codex app-server -c 'approval_policy="on-failure"' -c 'sandbox_mode="workspace-write"' -c 'model="o3"'
```

Common config keys:
| Key | Values | Description |
| --- | ------ | ----------- |
| `approval_policy` | `on-request`, `untrusted`, `on-failure`, `never` | When to prompt for approval |
| `sandbox_mode` | `read-only`, `workspace-write`, `danger-full-access` | File system access level |
| `model` | Model name string | AI model to use |

### 4.3 Exec Mode (Legacy)

**Basic headless execution:**
```bash
codex exec --json "Your prompt here"
```

**Resume session:**
```bash
codex exec --json resume --last "Continue with..."     # Resume most recent
codex exec --json resume <thread_id> "Continue with..."  # Resume specific
```

**Full auto mode:**
```bash
codex exec --json --full-auto "Your prompt"
```

### 4.4 Exec Mode CLI Arguments

| Argument                                   | Short | Description                       |
| ------------------------------------------ | ----- | --------------------------------- |
| `--json`                                   |       | Enable JSONL streaming to stdout  |
| `--output-last-message <file>`             | `-o`  | Write final message to file       |
| `--output-schema <file>`                   |       | JSON schema for structured output |
| `--full-auto`                              |       | Auto-approve with workspace sandbox |
| `--dangerously-bypass-approvals-and-sandbox` | `--yolo` | Full access, no sandboxing    |
| `--model <name>`                           | `-m`  | Model selection                   |
| `--cd <path>`                              | `-C`  | Working directory                 |
| `--sandbox <policy>`                       | `-s`  | Sandbox policy                    |
| `--image <file>`                           | `-i`  | Attach image(s)                   |
| `--add-dir <dir>`                          |       | Additional writable directories   |
| `--skip-git-repo-check`                    |       | Allow outside Git repos           |
| `resume`                                   |       | Resume session subcommand         |
| `--last`                                   |       | Resume most recent session        |

### 4.5 Exec Mode Input Format (stdin)

Exec mode does **NOT** support continuous JSONL input streaming. Each invocation
processes a single prompt. Approvals are auto-rejected.

**Input mechanism:**
- Prompt is passed as a command-line argument
- For multi-turn, spawn a new process with `codex exec resume <thread_id>`

**Multi-turn flow (process-per-turn):**
```bash
# Turn 1: Initial prompt
codex exec --json "Analyze the auth module"
# Output includes thread_id in thread.started event

# Turn 2: Resume with follow-up
codex exec --json resume <thread_id> "Now refactor it"

# Turn 3: Continue
codex exec --json resume <thread_id> "Add tests"
```

**Key difference from App-Server:** Exec mode requires a new process for each
turn and does not support interactive approvals.

### 4.6 Event Types

```typescript
type CodexEventType =
  // Session lifecycle
  | "thread.started"
  | "session_meta"      // Session metadata (app-server, stored in session files)
  // Turn lifecycle
  | "turn.started"
  | "turn.completed"
  | "turn.failed"
  // Item lifecycle
  | "item.started"
  | "item.updated"
  | "item.completed"
  // Approval (app-server mode only)
  | "approval.required"
  // Message history (stored in session files)
  | "event_msg"         // User/agent messages in session history
  // Errors
  | "error"
```

### 4.7 Item Types

```typescript
type CodexItemType =
  | "agent_message"      // Model text response (assistant output)
  | "reasoning"          // Internal chain-of-thought reasoning
  | "command_execution"  // Shell command execution (alias: "shell")
  | "tool_call"          // Generic tool call (alias for shell/command execution)
  | "shell"              // Shell command (alias for tool_call/command_execution)
  | "file_change"        // File create/modify/delete
  | "mcp_tool_call"      // MCP tool invocation
  | "web_search"         // Web search query and results
  | "todo_list"          // Task planning list
  | "error"              // Error during item processing

// Note: "tool_call" and "shell" are often used interchangeably in the JSONL
// output. Clients should treat them as equivalent to "command_execution".

// Item status values
type CodexItemStatus =
  | "in_progress"  // Item currently executing
  | "completed"    // Item completed successfully (alias: "success")
  | "failed"       // Item execution failed
  | "declined"     // Item was declined (e.g., user denied permission)
  | "skipped"      // Item was skipped

// File change kinds
type CodexFileChangeKind =
  | "add"     // New file created
  | "delete"  // File deleted
  | "update"  // File modified
```

### 4.8 Event Schemas

All item events include a full `item` object with an `id` field for correlation.

#### Thread Started
```json
{
  "type": "thread.started",
  "thread_id": "sess_abc123xyz"
}
```

#### Session Meta (App-Server Mode)
Session metadata stored in session files, containing session info including
working directory and git context:
```json
{
  "type": "session_meta",
  "payload": {
    "id": "sess_abc123xyz",
    "cwd": "/path/to/project",
    "timestamp": "2025-01-15T10:30:00Z",
    "model_provider": "openai",
    "git": {
      "branch": "main",
      "remote_url": "https://github.com/user/repo.git"
    }
  }
}
```

#### Approval Required (App-Server Mode)
Emitted when interactive approval is needed for a tool execution:
```json
{
  "type": "approval.required",
  "id": "approval_001",
  "turn_id": "turn_001",
  "action_type": "shell",
  "description": "Run: npm test",
  "tool_name": "bash",
  "tool_input": {
    "command": "npm test"
  },
  "command": "npm test",
  "file_path": null
}
```

**action_type values:** `shell`, `file_write`, `file_read`, `mcp_tool`

#### Event Message (Session History)
User and agent messages stored in session history files:
```json
{
  "type": "event_msg",
  "payload": {
    "type": "user_message",
    "message": "Analyze the authentication module"
  }
}
```

```json
{
  "type": "event_msg",
  "payload": {
    "type": "agent_message",
    "message": "I'll analyze the authentication module for you."
  }
}
```

**payload.type values:** `user_message`, `agent_message`

#### Turn Started
```json
{
  "type": "turn.started"
}
```

#### Item Started (Agent Message)
```json
{
  "type": "item.started",
  "item": {
    "id": "item_001",
    "type": "agent_message",
    "text": ""
  }
}
```

#### Item Updated (Agent Message)
```json
{
  "type": "item.updated",
  "item": {
    "id": "item_001",
    "type": "agent_message",
    "text": "I'll help you refactor..."
  }
}
```

#### Item Completed (Agent Message)
```json
{
  "type": "item.completed",
  "item": {
    "id": "item_001",
    "type": "agent_message",
    "text": "I'll help you refactor the authentication module."
  }
}
```

#### Item Updated (Command Execution)
```json
{
  "type": "item.updated",
  "item": {
    "id": "item_002",
    "type": "command_execution",
    "command": "npm test",
    "aggregated_output": "[PASS] auth.test.js\n[PASS] user.test.js\n",
    "exit_code": null,
    "status": "in_progress"
  }
}
```

#### Item Completed (Command Execution)
```json
{
  "type": "item.completed",
  "item": {
    "id": "item_002",
    "type": "command_execution",
    "command": "npm test",
    "aggregated_output": "[PASS] auth.test.js\n[PASS] user.test.js\n",
    "exit_code": 0,
    "status": "completed"
  }
}
```

#### Item Updated (File Change)
```json
{
  "type": "item.updated",
  "item": {
    "id": "item_003",
    "type": "file_change",
    "changes": [
      {
        "path": "src/auth.ts",
        "kind": "update"
      }
    ],
    "status": "in_progress"
  }
}
```

#### Item Completed (File Change)
```json
{
  "type": "item.completed",
  "item": {
    "id": "item_003",
    "type": "file_change",
    "changes": [
      {
        "path": "src/auth.ts",
        "kind": "update"
      }
    ],
    "status": "completed"
  }
}
```

#### Item Updated (MCP Tool Call)
```json
{
  "type": "item.updated",
  "item": {
    "id": "item_004",
    "type": "mcp_tool_call",
    "server": "database",
    "tool": "query",
    "arguments": {"sql": "SELECT * FROM users"},
    "result": null,
    "error": null,
    "status": "in_progress"
  }
}
```

#### Item Completed (MCP Tool Call)
```json
{
  "type": "item.completed",
  "item": {
    "id": "item_004",
    "type": "mcp_tool_call",
    "server": "database",
    "tool": "query",
    "arguments": {"sql": "SELECT * FROM users"},
    "result": {
      "content": [{"type": "text", "text": "[{\"id\":1,\"name\":\"Alice\"}]"}],
      "structured_content": null
    },
    "error": null,
    "status": "completed"
  }
}
```

#### Item Updated (Reasoning)
Internal chain-of-thought reasoning (visible in output):
```json
{
  "type": "item.updated",
  "item": {
    "id": "item_005",
    "type": "reasoning",
    "text": "I need to analyze the authentication flow..."
  }
}
```

#### Item Updated (Web Search)
```json
{
  "type": "item.updated",
  "item": {
    "id": "item_006",
    "type": "web_search",
    "query": "typescript async await best practices 2025"
  }
}
```

#### Item Updated (Todo List)
```json
{
  "type": "item.updated",
  "item": {
    "id": "item_007",
    "type": "todo_list",
    "items": [
      {"text": "Analyze current auth implementation", "completed": true},
      {"text": "Refactor to async/await", "completed": false},
      {"text": "Update tests", "completed": false}
    ]
  }
}
```

#### Item Updated (Error)
```json
{
  "type": "item.updated",
  "item": {
    "id": "item_008",
    "type": "error",
    "message": "Command exited with non-zero status"
  }
}
```

#### Turn Completed
```json
{
  "type": "turn.completed",
  "usage": {
    "input_tokens": 1250,
    "cached_input_tokens": 500,
    "output_tokens": 487
  }
}
```

#### Turn Failed
```json
{
  "type": "turn.failed",
  "error": {
    "message": "Tool execution failed: permission denied"
  }
}
```

#### Error
```json
{
  "type": "error",
  "message": "Session terminated unexpectedly"
}
```

### 4.9 Complete Event Flow Example

```jsonl
{"type":"thread.started","thread_id":"sess_abc123"}
{"type":"turn.started"}
{"type":"item.started","item":{"id":"1","type":"reasoning","text":""}}
{"type":"item.updated","item":{"id":"1","type":"reasoning","text":"I need to analyze the auth module first..."}}
{"type":"item.completed","item":{"id":"1","type":"reasoning","text":"I need to analyze the auth module first..."}}
{"type":"item.started","item":{"id":"2","type":"command_execution","command":"cat src/auth.ts","aggregated_output":"","exit_code":null,"status":"in_progress"}}
{"type":"item.updated","item":{"id":"2","type":"command_execution","command":"cat src/auth.ts","aggregated_output":"export function login() {...","exit_code":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"2","type":"command_execution","command":"cat src/auth.ts","aggregated_output":"export function login() {...","exit_code":0,"status":"completed"}}
{"type":"item.started","item":{"id":"3","type":"file_change","changes":[{"path":"src/auth.ts","kind":"update"}],"status":"in_progress"}}
{"type":"item.completed","item":{"id":"3","type":"file_change","changes":[{"path":"src/auth.ts","kind":"update"}],"status":"completed"}}
{"type":"item.started","item":{"id":"4","type":"agent_message","text":""}}
{"type":"item.updated","item":{"id":"4","type":"agent_message","text":"I've refactored the login function to be async."}}
{"type":"item.completed","item":{"id":"4","type":"agent_message","text":"I've refactored the login function to be async."}}
{"type":"turn.completed","usage":{"input_tokens":1250,"cached_input_tokens":500,"output_tokens":487}}
```

### 4.10 Permission Control

**Approval Policies:**

| Mode       | Flag          | Config Value | Behavior                      |
| ---------- | ------------- | ------------ | ----------------------------- |
| Untrusted  | `-a`          | `untrusted`  | Prompt for sensitive commands |
| On-request | (default)     | `on-request` | Prompt on escalation          |
| On-failure |               | `on-failure` | Prompt if sandbox blocks      |
| Full auto  | `--full-auto` | `never`      | No prompts                    |

**Sandbox Modes:**

| Mode        | Config Value         | Write     | Network |
| ----------- | -------------------- | --------- | ------- |
| Read-only   | `read-only`          | No        | No      |
| Workspace   | `workspace-write`    | CWD + tmp | No      |
| Full access | `danger-full-access` | All       | Yes     |

**Configuration (~/.codex/config.toml):**
```toml
[core]
approval_policy = "on-request"
sandbox_mode = "workspace-write"

[sandbox_workspace_write]
network_access = false
writable_roots = ["/additional/path"]
```

**Headless Permission Handling:**

Unlike Claude Code, Codex CLI does **not** emit explicit permission
request/response events in the stream. Permission handling is pre-configured
via:
1. Command-line flags (`--full-auto`, `-a`)
2. Configuration file (`~/.codex/config.toml`)
3. Sandbox enforcement (blocks disallowed operations)

For fully headless operation, use `--full-auto` to skip all permission prompts.
For security-conscious automation, use sandbox modes to restrict capabilities
instead of relying on runtime approval.

### 4.11 Session Storage

**Location:**
```
~/.codex/sessions/
```

---

## 5. Gemini CLI Protocol

### 5.1 Invocation

**Basic headless execution:**
```bash
gemini -p "Your prompt here" --output-format stream-json
```

**With piped input:**
```bash
cat file.txt | gemini -p "Analyze this" --output-format stream-json
```

**Resume session (combine with -p for headless multi-turn):**
```bash
gemini --resume -p "Continue"                    # Resume latest session
gemini --resume 1 -p "Continue"                  # By index
gemini --resume <session-uuid> -p "Continue"     # By session ID
```

**YOLO mode:**
```bash
gemini -p "prompt" --output-format stream-json -y
```

**Multi-turn headless flow (process-per-turn):**
```bash
# Turn 1: Initial prompt - captures session_id from init event
gemini -p "Analyze the auth module" --output-format stream-json -y
# Output: {"type":"init","session_id":"abc123",...}
# ... more JSONL events ...
# {"type":"result","status":"success",...}

# Turn 2: Resume with follow-up
gemini --resume abc123 -p "Now refactor it" --output-format stream-json -y

# Turn 3: Continue session
gemini --resume abc123 -p "Add comprehensive tests" --output-format stream-json -y
```

### 5.2 CLI Arguments

| Argument                 | Short | Description                       |
| ------------------------ | ----- | --------------------------------- |
| `--prompt <text>`        | `-p`  | Headless mode with prompt         |
| `--output-format <fmt>`  |       | `text`, `json`, or `stream-json`  |
| `--approval-mode <mode>` |       | `default`, `auto_edit`, or `yolo` |
| `--yolo`                 | `-y`  | Auto-approve all                  |
| `--auto-edit`            |       | Auto-approve file edits only      |
| `--sandbox`              |       | Enable Docker sandbox             |
| `--sandbox-image <img>`  |       | Custom sandbox image              |
| `--model <name>`         | `-m`  | Model selection                   |
| `--resume`               |       | Resume session                    |
| `--allowed-tools <list>` |       | Tool allowlist                    |
| `--debug`                | `-d`  | Enable debug output               |

### 5.3 Input Format (stdin)

Gemini CLI uses the **same process-per-turn architecture as Codex CLI**. Each
invocation processes a single prompt, and multi-turn conversations require
spawning new processes with the `--resume` flag.

**Input mechanism:**
- Prompt is passed via `-p` flag or piped to stdin as **plain text** (not JSONL)
- Internal tool loops are handled automatically within a single invocation
- Session state is **automatically persisted to disk** after each turn
- For multi-turn, spawn a new process with `--resume <session_id>`

**Session persistence:**
- Sessions are automatically saved to `~/.gemini/tmp/<project_hash>/chats/`
- The `session_id` is emitted in the `init` event at the start of each turn
- This ID can be used with `--resume` for subsequent turns

**Single-turn flow:**
```bash
gemini -p "Your prompt here" --output-format stream-json -y
```

**Multi-turn flow (process-per-turn, identical pattern to Codex):**
```bash
# Turn 1: Initial prompt - extract session_id from init event
gemini -p "Analyze the auth module" --output-format stream-json -y
# Output includes: {"type":"init","session_id":"abc123-def456","model":"gemini-2.0-flash-exp",...}

# Turn 2: Resume with follow-up (using session_id from Turn 1)
gemini --resume abc123-def456 -p "Now refactor it" --output-format stream-json -y

# Turn 3: Continue with same session_id
gemini --resume abc123-def456 -p "Add tests" --output-format stream-json -y
```

**Piped input (plain text, not JSONL):**
```bash
cat code.py | gemini -p "Review this code" --output-format stream-json
```

**Architecture comparison:**

| Aspect              | Codex CLI                | Gemini CLI                            |
| ------------------- | ------------------------ | ------------------------------------- |
| Process model       | Process-per-turn         | Process-per-turn                      |
| Session persistence | `~/.codex/sessions/`     | `~/.gemini/tmp/<project>/chats/`      |
| Resume flag         | `resume <thread_id>`     | `--resume <session_id>`               |
| Session ID source   | `thread.started` event   | `init` event                          |
| Stdin format        | Plain text               | Plain text                            |
| Output format       | JSONL (`--json`)         | JSONL (`--output-format stream-json`) |

**Key difference from Claude Code:** Both Codex and Gemini require a new process
for each user turn, with session state persisted to disk and restored via resume
flags. Claude Code is unique in supporting true bidirectional JSONL streaming
within a single long-lived process.

### 5.4 Event Types

```typescript
// Current event types (6 total)
type GeminiStreamEventType =
  | "init"        // Session initialization with session_id and model
  | "message"     // User/assistant message
  | "tool_use"    // Tool invocation request
  | "tool_result" // Tool execution result
  | "result"      // Session completion with stats
  | "error"       // Error event

// Result status values
type GeminiResultStatus =
  | "success"    // Completed successfully
  | "error"      // Completed with error

// Error severity levels
type GeminiErrorSeverity =
  | "warning"    // Non-fatal warning (e.g., loop detected)
  | "error"      // Fatal error

// Tool result status values
type GeminiToolResultStatus =
  | "success"    // Tool completed successfully
  | "error"      // Tool execution failed

// Tool result error types
type GeminiToolErrorType =
  | "FILE_NOT_FOUND"       // File not found
  | "TOOL_EXECUTION_ERROR" // General tool execution error
```

### 5.5 Event Schemas

#### Init Event
The first event emitted - contains session_id for multi-turn resume:
```json
{
  "type": "init",
  "timestamp": "2025-12-03T10:00:00.000Z",
  "session_id": "abc123-def456-7890",
  "model": "gemini-2.0-flash-exp"
}
```

#### Message Event (User)
```json
{
  "type": "message",
  "timestamp": "2025-12-03T10:00:01.000Z",
  "role": "user",
  "content": "Analyze the auth module"
}
```

#### Message Event (Assistant)
```json
{
  "type": "message",
  "timestamp": "2025-12-03T10:00:02.000Z",
  "role": "assistant",
  "content": "I'll analyze the authentication module...",
  "delta": true
}
```

#### Tool Use Event
```json
{
  "type": "tool_use",
  "timestamp": "2025-12-03T10:00:03.000Z",
  "tool_name": "Bash",
  "tool_id": "bash-123",
  "parameters": {
    "command": "ls -la src/auth/"
  }
}
```

#### Tool Result Event
```json
{
  "type": "tool_result",
  "timestamp": "2025-12-03T10:00:04.000Z",
  "tool_id": "bash-123",
  "status": "success",
  "output": "total 16\n-rw-r--r-- auth.ts\n-rw-r--r-- login.ts"
}
```

#### Result Event (Success)
```json
{
  "type": "result",
  "status": "success",
  "stats": {
    "total_tokens": 350,
    "input_tokens": 100,
    "output_tokens": 250,
    "thought_tokens": 0,
    "cache_tokens": 0,
    "tool_tokens": 0,
    "duration_ms": 5000,
    "tool_calls": 2
  },
  "timestamp": "2025-12-03T10:30:00Z"
}
```

#### Result Event (Error)
```json
{
  "type": "result",
  "status": "error",
  "stats": null,
  "error": {
    "code": "EXECUTION_FAILED",
    "message": "Tool execution timed out"
  },
  "timestamp": "2025-12-03T10:30:00Z"
}
```

#### Error Event
```json
{
  "type": "error",
  "timestamp": "2025-12-03T10:00:05.000Z",
  "severity": "warning",
  "message": "Loop detected, stopping execution"
}
```

**Note:** The `severity` field indicates the error severity:
- `"warning"`: Non-fatal warning (e.g., loop detected, max turns exceeded)
- `"error"`: Fatal error requiring session termination

### 5.6 Complete Event Flow Example

```jsonl
{"type":"init","timestamp":"2025-12-03T10:00:00.000Z","session_id":"abc123-def456","model":"gemini-2.0-flash-exp"}
{"type":"message","role":"user","content":"Analyze and refactor the auth module","timestamp":"2025-12-03T10:00:01.000Z"}
{"type":"tool_use","tool_name":"Bash","tool_id":"bash-001","parameters":{"command":"cat src/auth.ts"},"timestamp":"2025-12-03T10:00:02.000Z"}
{"type":"tool_result","tool_id":"bash-001","status":"success","output":"export function login() {...}","timestamp":"2025-12-03T10:00:03.000Z"}
{"type":"message","role":"assistant","content":"I found the login function. Let me make it async...","delta":true,"timestamp":"2025-12-03T10:00:04.000Z"}
{"type":"tool_use","tool_name":"write_file","tool_id":"write-001","parameters":{"file_path":"./src/auth.ts","content":"export async function login() {...}"},"timestamp":"2025-12-03T10:00:05.000Z"}
{"type":"tool_result","tool_id":"write-001","status":"success","timestamp":"2025-12-03T10:00:06.000Z"}
{"type":"message","role":"assistant","content":"Done! I've refactored the login function to be async.","timestamp":"2025-12-03T10:00:07.000Z"}
{"type":"result","status":"success","stats":{"total_tokens":350,"input_tokens":100,"output_tokens":250,"duration_ms":5000,"tool_calls":2},"timestamp":"2025-12-03T10:00:08.000Z"}
```

**Note:** The `session_id` from the `init` event (`abc123-def456`) can be used
to resume this session:
```bash
gemini --resume abc123-def456 -p "Add tests for the login function" --output-format stream-json
```

### 5.7 Permission Control

**Approval Modes:**

| Mode      | Flag            | Behavior                     |
| --------- | --------------- | ---------------------------- |
| Default   | (none)          | Prompt for each tool         |
| Auto-edit | `--auto-edit`   | Auto-approve file edits only |
| YOLO      | `-y` / `--yolo` | Auto-approve everything      |

**Per-server trust (settings.json):**
```json
{
  "mcpServers": {
    "trustedServer": {
      "command": "server",
      "trust": true
    }
  }
}
```

**Tool filtering:**
```json
{
  "mcpServers": {
    "myServer": {
      "includeTools": ["safe_read", "safe_write"],
      "excludeTools": ["dangerous_exec"]
    }
  }
}
```

**Headless Permission Handling:**

Gemini CLI does **not** emit explicit permission request/response events in the
stream. Like Codex, permissions are pre-configured via:
1. Command-line flags (`-y`, `--auto-edit`, `--approval-mode`)
2. Settings file trust configuration
3. Tool include/exclude lists

For fully headless operation, use `-y` (yolo) mode to auto-approve all
operations. There is no MCP-based permission delegation mechanism like Claude
Code's `--permission-prompt-tool`.

### 5.8 Session Management

**In-CLI commands:**
```
/chat save <tag>      # Save conversation
/chat resume <tag>    # Resume conversation
/chat list            # List conversations
/resume               # Interactive session browser
```

**CLI flags:**
```bash
gemini --resume              # Interactive picker
gemini --resume 1            # By index
gemini --resume <uuid>       # By ID
gemini --list-sessions       # List all sessions
```

**Session storage:**
```
~/.gemini/tmp/<project_hash>/chats/       # Session files
~/.gemini/tmp/<project_hash>/checkpoints/ # Git checkpoints
```

**Session file format:**

Unlike the streaming JSONL output, Gemini stores session history as a single JSON
file with a `messages` array. Session files are named
`session-YYYY-MM-DDTHH-MM-<short_id>.json`:

```json
{
  "sessionId": "abc123-def456-7890",
  "projectHash": "sha256hash...",
  "startTime": "2025-12-03T10:00:00.000Z",
  "lastUpdated": "2025-12-03T10:05:00.000Z",
  "messages": [
    {
      "id": "msg-001",
      "timestamp": "2025-12-03T10:00:01.000Z",
      "type": "user",
      "content": "Analyze the auth module"
    },
    {
      "id": "msg-002",
      "timestamp": "2025-12-03T10:00:05.000Z",
      "type": "gemini",
      "content": "I'll analyze the authentication module...",
      "thoughts": [
        {
          "subject": "Analysis Strategy",
          "description": "Starting with file structure review...",
          "timestamp": "2025-12-03T10:00:03.000Z"
        }
      ],
      "tokens": {
        "input": 100,
        "output": 250,
        "cached": 50,
        "thoughts": 100,
        "tool": 0,
        "total": 500
      },
      "model": "gemini-2.5-pro"
    }
  ]
}
```

**Message types in stored sessions:**

| Type     | Description                | Key Fields                             |
| -------- | -------------------------- | -------------------------------------- |
| `user`   | User prompt                | `content`                              |
| `gemini` | Assistant response         | `content`, `thoughts`, `tokens`        |

**Note:** The stored session format differs from the streaming JSONL format. When
reading session history, the `messages` array must be converted to event types:
- `type: "user"` → `GeminiMessageEvent` with `role: "user"`
- `type: "gemini"` → `GeminiMessageEvent` with `role: "assistant"`

**Checkpointing (settings.json):**
```json
{
  "general": {
    "checkpointing": {
      "enabled": true
    }
  }
}
```

---

## 6. Semantic Comparison

### 6.1 Invocation Comparison

| Action          | Claude Code                      | Codex CLI                        | Gemini CLI                      |
| --------------- | -------------------------------- | -------------------------------- | ------------------------------- |
| **Headless**    | `claude -p "prompt"`             | `codex "prompt"`                 | `gemini -p "prompt"`            |
| **Stream JSON** | `--output-format stream-json`    | `--json`                         | `--output-format stream-json`   |
| **Resume**      | `--resume <id>` or `-c`          | `resume <id>` or `resume --last` | `--resume` or `--resume <id>`   |
| **YOLO**        | `--dangerously-skip-permissions` | `--full-auto`                    | `-y` / `--yolo`                 |
| **Allowlist**   | `--allowedTools "Tool1,Tool2"`   | (config only)                    | `--allowed-tools "tool1,tool2"` |

### 6.2 Complete Event Type Catalog

#### Claude Code Events (10 types)

| Event Type      | Purpose                 | Fields                                          | Notes                                              |
| --------------- | ----------------------- | ----------------------------------------------- | -------------------------------------------------- |
| `system`        | System event            | `subtype`, varies by subtype                    | Subtypes: `init`, `compact_boundary`, `status`, `hook_response` |
| `user`          | User message            | `message`, `parent_tool_use_id`, `isSynthetic?` | User input or synthetic tool results               |
| `assistant`     | Assistant message       | `message`, `parent_tool_use_id`, `error?`       | Model responses                                    |
| `tool_use`      | Tool invocation request | `id`, `name`, `input`                           | Before tool executes (in assistant content)        |
| `tool_result`   | Tool execution result   | `tool_use_id`, `content`, `is_error`            | After tool completes (in user content)             |
| `tool_progress` | Tool execution progress | `tool_use_id`, `tool_name`, `elapsed_time_seconds` | Real-time progress updates                      |
| `result`        | Session completion      | `subtype`, `usage`, `modelUsage`, `permission_denials` | Final event with detailed stats              |
| `error`         | Error occurred          | `error.type`, `error.message`                   | May occur any time                                 |
| `stream_event`  | Raw API delta           | `event`, `parent_tool_use_id`                   | With `includePartialMessages`                      |
| `auth_status`   | Auth state              | `isAuthenticating`, `output[]`, `error?`        | Authentication updates                             |

#### Codex CLI Events (8 types + 8 item types)

**Session/Turn Events:**

| Event Type       | Purpose              | Fields          | Notes                  |
| ---------------- | -------------------- | --------------- | ---------------------- |
| `thread.started` | Session start        | `thread_id`     | First event emitted    |
| `turn.started`   | Turn lifecycle start | (none)          | Before items           |
| `turn.completed` | Turn lifecycle end   | `usage`         | Contains token counts  |
| `turn.failed`    | Turn failure         | `error.message` | On unrecoverable error |
| `error`          | Session-level error  | `message`       | May occur any time     |

**Item Lifecycle Events:**

| Event Type       | Purpose       | Fields                | Notes                       |
| ---------------- | ------------- | --------------------- | --------------------------- |
| `item.started`   | Item begins   | `item` object         | Start of item processing    |
| `item.updated`   | Item progress | `item` object         | Streaming updates           |
| `item.completed` | Item finished | `item` object         | End of item processing      |

**Item Object Structure:**
All item events contain a full `item` object with an `id` field for correlation and a `type` field indicating the item type.

**Item Types (8):**

| Item Type           | Purpose           | Key Fields in `item`                             |
| ------------------- | ----------------- | ------------------------------------------------ |
| `agent_message`     | Assistant text    | `text`                                           |
| `reasoning`         | Chain-of-thought  | `text`                                           |
| `command_execution` | Shell command     | `command`, `aggregated_output`, `exit_code`, `status` |
| `file_change`       | File modification | `changes[]` with `path`, `kind`; `status`        |
| `mcp_tool_call`     | MCP tool          | `server`, `tool`, `arguments`, `result`, `error`, `status` |
| `web_search`        | Web search        | `query`                                          |
| `todo_list`         | Task planning     | `items[]` with `text`, `completed`               |
| `error`             | Error item        | `message`                                        |

**Item Status Values:** `in_progress`, `completed`, `failed`, `declined`, `skipped`

#### Gemini CLI Events (6 types)

| Event Type    | Purpose                  | Fields                                                | Notes                                       |
| ------------- | ------------------------ | ----------------------------------------------------- | ------------------------------------------- |
| `init`        | Session start            | `session_id`, `model`, `timestamp`                    | First event, contains session ID for resume |
| `message`     | User/assistant message   | `role`, `content`, `delta?`, `timestamp`              | Supports streaming via delta flag           |
| `tool_use`    | Tool invocation request  | `tool_name`, `tool_id`, `parameters`, `timestamp`     | Before tool executes                        |
| `tool_result` | Tool execution result    | `tool_id`, `status`, `output?`, `error?`, `timestamp` | After tool completes                        |
| `result`      | Session completion       | `status`, `stats`, `timestamp`, `error?`              | Final event                                 |
| `error`       | Error event              | `severity`, `message`, `timestamp`                    | Severity: `warning` or `error`              |

### 6.3 Comprehensive Event Mapping Matrix

This matrix maps every event type across all three CLIs:

| Semantic Concept           | Claude Code                          | Codex CLI                          | Gemini CLI                        |
| -------------------------- | ------------------------------------ | ---------------------------------- | --------------------------------- |
| **Session Lifecycle**      |                                      |                                    |                                   |
| Session start              | `system` (subtype: init)             | `thread.started`                   | `init`                            |
| Session end (success)      | `result` (subtype: success)          | (process exit 0)                   | `result` (status: success)        |
| Session end (error)        | `result` (subtype: error_*)          | `turn.failed`                      | `result` (status: error)          |
| **Turn Lifecycle**         |                                      |                                    |                                   |
| Turn start                 | (implicit)                           | `turn.started`                     | (implicit)                        |
| Turn end                   | (implicit)                           | `turn.completed`                   | (implicit in result)              |
| Turn failed                | `error`                              | `turn.failed`                      | `error` (severity: error)         |
| **Content Events**         |                                      |                                    |                                   |
| Assistant text             | `assistant`                          | `item.*` (agent_message)           | `message` (role: assistant)       |
| User message               | `user`                               | -                                  | `message` (role: user)            |
| Streaming text             | `stream_event`                       | `item.updated` (agent_message)     | `message` (delta: true)           |
| **Tool Lifecycle**         |                                      |                                    |                                   |
| Tool invocation start      | `tool_use` (in assistant content)    | `item.started` (command/mcp/file)  | `tool_use`                        |
| Tool progress/output       | `tool_progress`                      | `item.updated`                     | -                                 |
| Tool completed (success)   | `tool_result` (in user content)      | `item.completed` (status: completed) | `tool_result` (status: success) |
| Tool completed (error)     | `tool_result` (is_error: true)       | `item.completed` (status: failed)  | `tool_result` (status: error)     |
| Tool declined              | (permission_denials in result)       | `item.completed` (status: declined) | -                                |
| **Specific Tool Types**    |                                      |                                    |                                   |
| Shell command              | `tool_use` (name: Bash)              | `item.*` (command_execution)       | `tool_use` (tool_name: Bash)      |
| File read                  | `tool_use` (name: Read)              | `item.*` (command_execution)       | `tool_use` (tool_name: read_file) |
| File write/edit            | `tool_use` (name: Edit/Write)        | `item.*` (file_change)             | `tool_use` (tool_name: write_file)|
| MCP tool                   | `tool_use` (name: mcp__*)            | `item.*` (mcp_tool_call)           | `tool_use` (MCP name)             |
| Web search                 | `tool_use` (name: WebSearch)         | `item.*` (web_search)              | `tool_use` (tool_name: google_search) |
| **Reasoning/Thinking**     |                                      |                                    |                                   |
| Visible reasoning          | -                                    | `item.*` (reasoning)               | -                                 |
| Internal thinking          | (not exposed)                        | (text in reasoning)                | (not exposed)                     |
| **Task Management**        |                                      |                                    |                                   |
| Todo list                  | `tool_use` (name: TodoWrite)         | `item.*` (todo_list)               | -                                 |
| **System Events**          |                                      |                                    |                                   |
| System init info           | `system` (subtype: init)             | -                                  | -                                 |
| Context compaction         | `system` (subtype: compact_boundary) | -                                  | -                                 |
| Status updates             | `system` (subtype: status)           | -                                  | -                                 |
| Hook responses             | `system` (subtype: hook_response)    | -                                  | -                                 |
| Auth status                | `auth_status`                        | -                                  | -                                 |
| Verbose/debug              | `stream_event`                       | -                                  | (--debug to stderr)               |
| **Error Handling**         |                                      |                                    |                                   |
| Session error              | `error`                              | `error`                            | `error` (severity: error)         |
| Warning                    | -                                    | -                                  | `error` (severity: warning)       |
| Tool error                 | `tool_result` (is_error: true)       | `item.*` (error item_type)         | `tool_result` (status: error)     |
| **Token/Usage Tracking**   |                                      |                                    |                                   |
| Per-turn usage             | -                                    | `turn.completed.usage`             | -                                 |
| Final usage                | `result.usage`, `result.modelUsage`  | `turn.completed.usage`             | `result.stats`                    |
| Cost tracking              | `result.total_cost_usd`              | -                                  | -                                 |
| **Permission Events**      |                                      |                                    |                                   |
| Permission request         | (via MCP tool call / canUseTool)     | -                                  | -                                 |
| Permission denials         | `result.permission_denials`          | -                                  | -                                 |

### 6.4 Permission Mode Mapping

| Behavior                      | Claude Code                          | Codex CLI          | Gemini CLI  |
| ----------------------------- | ------------------------------------ | ------------------ | ----------- |
| **Ask for all**               | `permissionMode: "default"`          | `untrusted` / `-a` | `default`   |
| **Ask dangerous only**        | (via hooks)                          | `on-request`       | -           |
| **Auto file edits**           | `permissionMode: "acceptEdits"`      | -                  | `auto_edit` |
| **Auto all**                  | `permissionMode: "bypassPermissions"` | `--full-auto`     | `--yolo`    |
| **Plan only (no execution)**  | `permissionMode: "plan"`             | -                  | -           |
| **Deny if not pre-approved**  | `permissionMode: "dontAsk"`          | -                  | -           |
| **CLI YOLO**                  | `--dangerously-skip-permissions`     | `--full-auto`      | `-y`        |
| **Sandbox**                   | (via SDK sandbox settings)           | `workspace-write`  | `--sandbox` |
| **MCP Permission Delegation** | `--permission-prompt-tool`           | -                  | -           |
| **SDK Permission Callback**   | `canUseTool` callback                | -                  | -           |

### 6.5 Feature Comparison

| Feature                   | Claude Code                  | Codex CLI                  | Gemini CLI         |
| ------------------------- | ---------------------------- | -------------------------- | ------------------ |
| **Streaming granularity** | Per-message                  | Per-item-update            | Per-message        |
| **Tool lifecycle events** | 3 (use/progress/result)      | 3 (start/update/complete)  | 2 (use/result)     |
| **Reasoning visibility**  | No                           | Yes (`reasoning` item)     | No                 |
| **Token tracking**        | Yes (result.usage)           | Yes (turn.completed.usage) | Yes (result.stats) |
| **Cost tracking**         | Yes (total_cost_usd)         | No                         | No                 |
| **Per-model usage**       | Yes (modelUsage)             | No                         | No                 |
| **Structured output**     | `outputFormat` schema        | `--output-schema`          | No                 |
| **Partial streaming**     | `includePartialMessages`     | Built-in (item.updated)    | Built-in (delta)   |
| **MCP integration**       | Yes                          | Yes                        | Yes                |
| **Git checkpointing**     | No                           | No                         | Yes                |
| **Permission delegation** | MCP tool + canUseTool        | Config only                | Config only        |
| **Session forking**       | Yes (forkSession)            | No                         | No                 |
| **Hook system**           | Yes (PreToolUse, etc.)       | No                         | No                 |
| **Beta features**         | Yes (betas array)            | No                         | No                 |

### 6.6 Event Flow Patterns

**Claude Code:**
```
system.init → user → assistant → (tool_progress)* → user(synthetic) → assistant* → result
```

**Codex CLI:**
```
thread.started → turn.started →
  (item.started → item.updated* → item.completed)* →
turn.completed
```

**Gemini CLI:**
```
init → message(user) → (tool_use → tool_result)* → message(assistant)* → result
```

**Key Differences:**
- **Claude Code:** Long-lived bidirectional JSONL process with user/assistant message events
- **Codex CLI:** Process-per-turn with item-based granularity
- **Gemini CLI:** Process-per-turn with message-based events (similar to Claude but no bidirectional input)

---

## 7. Unified Protocol Specification

### 7.1 Design Goals

1. **Stdio-first:** All protocols use process spawning with JSONL streaming
2. **Event-driven:** Normalized event lifecycle for tools and messages
3. **Type-safe:** Strong Dart typing with sealed classes
4. **Lossless:** Preserve all native event information
5. **Extensible:** Support additional CLIs without breaking changes

### 7.2 Unified Event Model

```dart
/// Base event type - sealed for exhaustive pattern matching
sealed class AgentEvent {
  final String id;
  final String sessionId;
  final DateTime timestamp;
}

/// Session started
final class SessionStartedEvent extends AgentEvent {
  final String agentType;  // "claude" | "codex" | "gemini"
  final SessionConfig config;
}

/// Text content streamed
final class TextChunkEvent extends AgentEvent {
  final String content;
  final bool isPartial;
  final String? role;  // "assistant" | "user" | null
}

/// Tool execution started
final class ToolStartedEvent extends AgentEvent {
  final String toolId;
  final String toolName;
  final Map<String, dynamic> arguments;
}

/// Tool execution progress (Codex only)
final class ToolProgressEvent extends AgentEvent {
  final String toolId;
  final String? output;
  final double? progress;
}

/// Tool execution completed
final class ToolCompletedEvent extends AgentEvent {
  final String toolId;
  final bool success;
  final dynamic result;
  final String? error;
}

/// File modification
final class FileChangedEvent extends AgentEvent {
  final String filePath;
  final FileChangeType changeType;
  final String? diff;
  final String? before;
  final String? after;
}

/// Turn completed with usage stats
final class TurnCompletedEvent extends AgentEvent {
  final TokenUsage? usage;
  final Duration? duration;
}

/// Session ended
final class SessionEndedEvent extends AgentEvent {
  final SessionEndReason reason;
  final String? error;
  final TokenUsage? finalUsage;
}

/// Enums
enum FileChangeType { created, modified, deleted }
enum SessionEndReason { completed, failed, cancelled, timeout }

/// Token usage stats
class TokenUsage {
  final int inputTokens;
  final int outputTokens;
  final int? cachedTokens;
  final int? reasoningTokens;
  final int totalTokens;
}
```

### 7.3 Session Configuration

```dart
/// Unified session configuration
class SessionConfig {
  final AgentType agentType;
  final String prompt;
  final String? sessionId;  // For resume
  final String? workingDirectory;
  final String? model;
  final ApprovalMode approvalMode;
  final SandboxMode sandboxMode;
  final List<String>? allowedTools;
  final List<String>? blockedTools;
  final int? maxTurns;
  final Map<String, String>? environment;
}

enum AgentType { claude, codex, gemini }

enum ApprovalMode {
  ask,          // Prompt for every tool
  askDangerous, // Prompt only for dangerous tools
  autoEdit,     // Auto-approve file operations
  autoAll,      // Auto-approve everything (YOLO)
}

enum SandboxMode {
  none,           // No sandboxing
  readOnly,       // Read-only access
  workspaceWrite, // Write to workspace only
  fullAccess,     // Unrestricted
}
```

### 7.4 Protocol Adapters

```dart
/// Base adapter interface
abstract class ProtocolAdapter {
  /// Convert native JSONL line to unified event
  AgentEvent? parseEvent(String jsonLine);

  /// Build CLI arguments from config
  List<String> buildArgs(SessionConfig config);

  /// Get CLI executable name
  String get executable;
}

/// Claude adapter
class ClaudeAdapter implements ProtocolAdapter {
  @override
  String get executable => 'claude';

  @override
  List<String> buildArgs(SessionConfig config) {
    return [
      '-p', config.prompt,
      '--output-format', 'stream-json',
      if (config.sessionId != null) ...['--resume', config.sessionId!],
      if (config.approvalMode == ApprovalMode.autoAll)
        '--dangerously-skip-permissions',
      if (config.allowedTools != null)
        ...['--allowedTools', config.allowedTools!.join(',')],
      if (config.maxTurns != null)
        ...['--max-turns', config.maxTurns.toString()],
    ];
  }

  @override
  AgentEvent? parseEvent(String jsonLine) {
    final json = jsonDecode(jsonLine);
    return switch (json['type']) {
      'init' => SessionStartedEvent(...),
      'message' => TextChunkEvent(...),
      'tool_use' => ToolStartedEvent(...),
      'tool_result' => ToolCompletedEvent(...),
      'result' => SessionEndedEvent(...),
      'error' => SessionEndedEvent(reason: SessionEndReason.failed, ...),
      _ => null,
    };
  }
}

/// Codex adapter
class CodexAdapter implements ProtocolAdapter {
  @override
  String get executable => 'codex';

  @override
  List<String> buildArgs(SessionConfig config) {
    return [
      'exec',
      '--output-jsonl',
      config.prompt,
      if (config.sessionId != null) ...['--resume', config.sessionId!],
      if (config.approvalMode == ApprovalMode.autoAll) '--full-auto',
      if (config.approvalMode == ApprovalMode.ask) '-a',
      if (config.workingDirectory != null)
        ...['--cd', config.workingDirectory!],
    ];
  }

  @override
  AgentEvent? parseEvent(String jsonLine) {
    final json = jsonDecode(jsonLine);
    return switch (json['type']) {
      'thread.started' => SessionStartedEvent(...),
      'item.updated' => _parseItemUpdated(json),
      'item.completed' => _parseItemCompleted(json),
      'turn.completed' => TurnCompletedEvent(...),
      'turn.failed' => SessionEndedEvent(reason: SessionEndReason.failed, ...),
      'error' => SessionEndedEvent(reason: SessionEndReason.failed, ...),
      _ => null,
    };
  }
}

/// Gemini adapter
class GeminiAdapter implements ProtocolAdapter {
  @override
  String get executable => 'gemini';

  @override
  List<String> buildArgs(SessionConfig config) {
    return [
      '-p', config.prompt,
      '--output-format', 'stream-json',
      if (config.sessionId != null) ...['--resume', config.sessionId!],
      if (config.approvalMode == ApprovalMode.autoAll) '-y',
      if (config.approvalMode == ApprovalMode.autoEdit) '--auto-edit',
      if (config.model != null) ...['--model', config.model!],
    ];
  }

  @override
  AgentEvent? parseEvent(String jsonLine) {
    final json = jsonDecode(jsonLine);
    return switch (json['type']) {
      // Modern event types
      'init' => SessionStartedEvent(sessionId: json['session_id'], ...),
      'message' => TextChunkEvent(
        content: json['content'],
        isPartial: json['delta'] == true,
        role: json['role'],
        ...
      ),
      'tool_use' => ToolStartedEvent(
        toolId: json['tool_id'],
        toolName: json['tool_name'],
        arguments: json['parameters'],
        ...
      ),
      'tool_result' => ToolCompletedEvent(
        toolId: json['tool_id'],
        success: json['status'] == 'success',
        result: json['output'],
        error: json['error']?['message'],
        ...
      ),
      // Legacy event types (still supported)
      'content' => TextChunkEvent(content: json['value'], ...),
      'tool_call' => ToolStartedEvent(...),  // + implicit ToolCompletedEvent
      // Session lifecycle
      'result' => SessionEndedEvent(
        reason: json['status'] == 'success'
          ? SessionEndReason.completed
          : SessionEndReason.failed,
        ...
      ),
      'error' => SessionEndedEvent(reason: SessionEndReason.failed, ...),
      'retry' => null,  // Informational, usually not translated
      _ => null,
    };
  }
}
```

### 7.5 Event Translation Matrix

#### From Claude Code
| Native Event                                 | Unified Event(s)                               |
| -------------------------------------------- | ---------------------------------------------- |
| `type: "init"`                               | `SessionStartedEvent`                          |
| `type: "message"`                            | `TextChunkEvent`                               |
| `type: "message"` (partial: true)            | `TextChunkEvent` (isPartial: true)             |
| `type: "tool_use"`                           | `ToolStartedEvent`                             |
| `type: "tool_result"`                        | `ToolCompletedEvent`                           |
| `type: "result"` (success)                   | `SessionEndedEvent(completed)`                 |
| `type: "result"` (error)                     | `SessionEndedEvent(failed)`                    |
| `type: "error"`                              | `SessionEndedEvent(failed)`                    |
| `type: "system"` (subtype: init)             | `SystemEvent` (informational, usually ignored) |
| `type: "system"` (subtype: compact_boundary) | `SystemEvent` (context management)             |
| `type: "stream_event"`                       | `RawDeltaEvent` (verbose mode only)            |

#### From Codex CLI
| Native Event                         | Unified Event(s)                       |
| ------------------------------------ | -------------------------------------- |
| `thread.started`                     | `SessionStartedEvent`                  |
| `turn.started`                       | `TurnStartedEvent` (optional)          |
| `item.started` (agent_message)       | `TextChunkEvent` (start)               |
| `item.updated` (agent_message)       | `TextChunkEvent` (streaming)           |
| `item.completed` (agent_message)     | `TextChunkEvent` (final)               |
| `item.started` (reasoning)           | `ReasoningEvent` (start)               |
| `item.updated` (reasoning)           | `ReasoningEvent` (streaming)           |
| `item.completed` (reasoning)         | `ReasoningEvent` (final)               |
| `item.started` (command_execution)   | `ToolStartedEvent` (shell)             |
| `item.updated` (command_execution)   | `ToolProgressEvent` (output streaming) |
| `item.completed` (command_execution) | `ToolCompletedEvent` (shell)           |
| `item.started` (file_change)         | `FileChangedEvent` (start)             |
| `item.updated` (file_change)         | `FileChangedEvent` (diff details)      |
| `item.completed` (file_change)       | `FileChangedEvent` (final)             |
| `item.started` (mcp_tool_call)       | `ToolStartedEvent` (MCP)               |
| `item.updated` (mcp_tool_call)       | `ToolProgressEvent` (MCP)              |
| `item.completed` (mcp_tool_call)     | `ToolCompletedEvent` (MCP)             |
| `item.started` (web_search)          | `ToolStartedEvent` (search)            |
| `item.updated` (web_search)          | `ToolProgressEvent` (results)          |
| `item.completed` (web_search)        | `ToolCompletedEvent` (search)          |
| `item.*` (todo_list)                 | `TodoListEvent`                        |
| `item.*` (error)                     | `ErrorEvent`                           |
| `turn.completed`                     | `TurnCompletedEvent`                   |
| `turn.failed`                        | `SessionEndedEvent(failed)`            |
| `error`                              | `SessionEndedEvent(failed)`            |
| (process exit 0)                     | `SessionEndedEvent(completed)`         |

#### From Gemini CLI
| Native Event                        | Unified Event(s)                                      |
| ----------------------------------- | ----------------------------------------------------- |
| `type: "init"`                      | `SessionStartedEvent`                                 |
| `type: "message"` (role: user)      | (informational, not translated)                       |
| `type: "message"` (role: assistant) | `TextChunkEvent`                                      |
| `type: "message"` (delta: true)     | `TextChunkEvent` (isPartial: true)                    |
| `type: "tool_use"`                  | `ToolStartedEvent`                                    |
| `type: "tool_result"` (success)     | `ToolCompletedEvent`                                  |
| `type: "tool_result"` (error)       | `ToolCompletedEvent` (success: false)                 |
| `type: "content"` (legacy)          | `TextChunkEvent`                                      |
| `type: "tool_call"` (legacy)        | `ToolStartedEvent` + `ToolCompletedEvent` (atomic)    |
| `type: "result"` (success)          | `TurnCompletedEvent` + `SessionEndedEvent(completed)` |
| `type: "result"` (error)            | `SessionEndedEvent(failed)`                           |
| `type: "result"` (cancelled)        | `SessionEndedEvent(cancelled)`                        |
| `type: "error"`                     | `SessionEndedEvent(failed)`                           |
| `type: "retry"`                     | `RetryEvent` (transient failure handling)             |

---

## 8. JSON Schema Definitions

### 8.1 Unified Event Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://agent-protocol.dev/schemas/unified-event.json",
  "title": "UnifiedAgentEvent",
  "oneOf": [
    { "$ref": "#/$defs/SessionStartedEvent" },
    { "$ref": "#/$defs/TextChunkEvent" },
    { "$ref": "#/$defs/ToolStartedEvent" },
    { "$ref": "#/$defs/ToolProgressEvent" },
    { "$ref": "#/$defs/ToolCompletedEvent" },
    { "$ref": "#/$defs/FileChangedEvent" },
    { "$ref": "#/$defs/TurnCompletedEvent" },
    { "$ref": "#/$defs/SessionEndedEvent" }
  ],
  "$defs": {
    "BaseEvent": {
      "type": "object",
      "required": ["id", "sessionId", "timestamp", "type"],
      "properties": {
        "id": { "type": "string" },
        "sessionId": { "type": "string" },
        "timestamp": { "type": "string", "format": "date-time" },
        "type": { "type": "string" }
      }
    },
    "SessionStartedEvent": {
      "allOf": [
        { "$ref": "#/$defs/BaseEvent" },
        {
          "properties": {
            "type": { "const": "sessionStarted" },
            "agentType": { "enum": ["claude", "codex", "gemini"] },
            "config": { "$ref": "#/$defs/SessionConfig" }
          },
          "required": ["agentType"]
        }
      ]
    },
    "TextChunkEvent": {
      "allOf": [
        { "$ref": "#/$defs/BaseEvent" },
        {
          "properties": {
            "type": { "const": "textChunk" },
            "content": { "type": "string" },
            "isPartial": { "type": "boolean" },
            "role": { "enum": ["assistant", "user", null] }
          },
          "required": ["content"]
        }
      ]
    },
    "ToolStartedEvent": {
      "allOf": [
        { "$ref": "#/$defs/BaseEvent" },
        {
          "properties": {
            "type": { "const": "toolStarted" },
            "toolId": { "type": "string" },
            "toolName": { "type": "string" },
            "arguments": { "type": "object" }
          },
          "required": ["toolId", "toolName"]
        }
      ]
    },
    "ToolProgressEvent": {
      "allOf": [
        { "$ref": "#/$defs/BaseEvent" },
        {
          "properties": {
            "type": { "const": "toolProgress" },
            "toolId": { "type": "string" },
            "output": { "type": "string" },
            "progress": { "type": "number", "minimum": 0, "maximum": 1 }
          },
          "required": ["toolId"]
        }
      ]
    },
    "ToolCompletedEvent": {
      "allOf": [
        { "$ref": "#/$defs/BaseEvent" },
        {
          "properties": {
            "type": { "const": "toolCompleted" },
            "toolId": { "type": "string" },
            "success": { "type": "boolean" },
            "result": {},
            "error": { "type": "string" }
          },
          "required": ["toolId", "success"]
        }
      ]
    },
    "FileChangedEvent": {
      "allOf": [
        { "$ref": "#/$defs/BaseEvent" },
        {
          "properties": {
            "type": { "const": "fileChanged" },
            "filePath": { "type": "string" },
            "changeType": { "enum": ["created", "modified", "deleted"] },
            "diff": { "type": "string" },
            "before": { "type": "string" },
            "after": { "type": "string" }
          },
          "required": ["filePath", "changeType"]
        }
      ]
    },
    "TurnCompletedEvent": {
      "allOf": [
        { "$ref": "#/$defs/BaseEvent" },
        {
          "properties": {
            "type": { "const": "turnCompleted" },
            "usage": { "$ref": "#/$defs/TokenUsage" },
            "durationMs": { "type": "integer" }
          }
        }
      ]
    },
    "SessionEndedEvent": {
      "allOf": [
        { "$ref": "#/$defs/BaseEvent" },
        {
          "properties": {
            "type": { "const": "sessionEnded" },
            "reason": { "enum": ["completed", "failed", "cancelled", "timeout"] },
            "error": { "type": "string" },
            "finalUsage": { "$ref": "#/$defs/TokenUsage" }
          },
          "required": ["reason"]
        }
      ]
    },
    "SessionConfig": {
      "type": "object",
      "properties": {
        "agentType": { "enum": ["claude", "codex", "gemini"] },
        "workingDirectory": { "type": "string" },
        "model": { "type": "string" },
        "approvalMode": { "enum": ["ask", "askDangerous", "autoEdit", "autoAll"] },
        "sandboxMode": { "enum": ["none", "readOnly", "workspaceWrite", "fullAccess"] },
        "allowedTools": { "type": "array", "items": { "type": "string" } },
        "blockedTools": { "type": "array", "items": { "type": "string" } },
        "maxTurns": { "type": "integer" }
      }
    },
    "TokenUsage": {
      "type": "object",
      "properties": {
        "inputTokens": { "type": "integer" },
        "outputTokens": { "type": "integer" },
        "cachedTokens": { "type": "integer" },
        "reasoningTokens": { "type": "integer" },
        "totalTokens": { "type": "integer" }
      },
      "required": ["inputTokens", "outputTokens", "totalTokens"]
    }
  }
}
```

### 8.2 Native Protocol Schemas

#### Claude Code Event Schema
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://agent-protocol.dev/schemas/claude-event.json",
  "title": "ClaudeStreamEvent",
  "oneOf": [
    {
      "description": "System event (init, compact_boundary, status, hook_response)",
      "properties": {
        "type": { "const": "system" },
        "subtype": { "enum": ["init", "compact_boundary", "status", "hook_response"] },
        "uuid": { "type": "string" },
        "session_id": { "type": "string" },
        "claude_code_version": { "type": "string" },
        "cwd": { "type": "string" },
        "tools": { "type": "array", "items": { "type": "string" } },
        "model": { "type": "string" },
        "permissionMode": { "enum": ["default", "acceptEdits", "bypassPermissions", "plan", "dontAsk"] }
      },
      "required": ["type", "subtype", "session_id"]
    },
    {
      "description": "User message",
      "properties": {
        "type": { "const": "user" },
        "uuid": { "type": "string" },
        "session_id": { "type": "string" },
        "message": { "type": "object" },
        "parent_tool_use_id": { "type": ["string", "null"] },
        "isSynthetic": { "type": "boolean" },
        "isReplay": { "type": "boolean" }
      },
      "required": ["type", "session_id", "message"]
    },
    {
      "description": "Assistant message",
      "properties": {
        "type": { "const": "assistant" },
        "uuid": { "type": "string" },
        "session_id": { "type": "string" },
        "message": { "type": "object" },
        "parent_tool_use_id": { "type": ["string", "null"] },
        "error": { "enum": ["authentication_failed", "billing_error", "rate_limit", "invalid_request", "server_error", "unknown", null] }
      },
      "required": ["type", "session_id", "message"]
    },
    {
      "description": "Tool progress",
      "properties": {
        "type": { "const": "tool_progress" },
        "uuid": { "type": "string" },
        "session_id": { "type": "string" },
        "tool_use_id": { "type": "string" },
        "tool_name": { "type": "string" },
        "elapsed_time_seconds": { "type": "number" }
      },
      "required": ["type", "session_id", "tool_use_id", "tool_name"]
    },
    {
      "description": "Result (success or error)",
      "properties": {
        "type": { "const": "result" },
        "subtype": { "enum": ["success", "error_during_execution", "error_max_turns", "error_max_budget_usd", "error_max_structured_output_retries"] },
        "uuid": { "type": "string" },
        "session_id": { "type": "string" },
        "duration_ms": { "type": "integer" },
        "is_error": { "type": "boolean" },
        "num_turns": { "type": "integer" },
        "total_cost_usd": { "type": "number" },
        "usage": { "type": "object" },
        "modelUsage": { "type": "object" },
        "permission_denials": { "type": "array" }
      },
      "required": ["type", "subtype", "session_id"]
    },
    {
      "description": "Error event",
      "properties": {
        "type": { "const": "error" },
        "error": {
          "type": "object",
          "properties": {
            "type": { "type": "string" },
            "message": { "type": "string" }
          }
        }
      },
      "required": ["type", "error"]
    },
    {
      "description": "Stream event (partial messages)",
      "properties": {
        "type": { "const": "stream_event" },
        "uuid": { "type": "string" },
        "session_id": { "type": "string" },
        "event": { "type": "object" },
        "parent_tool_use_id": { "type": ["string", "null"] }
      },
      "required": ["type", "session_id", "event"]
    },
    {
      "description": "Auth status",
      "properties": {
        "type": { "const": "auth_status" },
        "uuid": { "type": "string" },
        "session_id": { "type": "string" },
        "isAuthenticating": { "type": "boolean" },
        "output": { "type": "array", "items": { "type": "string" } },
        "error": { "type": ["string", "null"] }
      },
      "required": ["type", "session_id", "isAuthenticating"]
    }
  ]
}
```

#### Codex CLI Event Schema
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://agent-protocol.dev/schemas/codex-event.json",
  "title": "CodexStreamEvent",
  "$defs": {
    "Item": {
      "type": "object",
      "required": ["id", "type"],
      "properties": {
        "id": { "type": "string", "description": "Unique item identifier" },
        "type": { "enum": ["agent_message", "command_execution", "file_edit", "input_request"] },
        "status": { "enum": ["in_progress", "completed", "failed", "declined"] },
        "text": { "type": "string" },
        "command": { "type": "string" },
        "file_path": { "type": "string" },
        "diff": { "type": "string" },
        "exit_code": { "type": "integer" }
      }
    }
  },
  "oneOf": [
    {
      "description": "Thread started - contains thread_id for multi-turn resume",
      "properties": {
        "type": { "const": "thread.started" },
        "thread_id": { "type": "string" }
      },
      "required": ["type", "thread_id"]
    },
    {
      "description": "Turn started",
      "properties": { "type": { "const": "turn.started" } },
      "required": ["type"]
    },
    {
      "description": "Turn completed with token usage",
      "properties": {
        "type": { "const": "turn.completed" },
        "usage": {
          "type": "object",
          "properties": {
            "input_tokens": { "type": "integer" },
            "cached_input_tokens": { "type": "integer" },
            "output_tokens": { "type": "integer" },
            "reasoning_tokens": { "type": "integer" }
          },
          "required": ["input_tokens", "output_tokens"]
        }
      },
      "required": ["type", "usage"]
    },
    {
      "description": "Turn failed with error",
      "properties": {
        "type": { "const": "turn.failed" },
        "error": {
          "type": "object",
          "properties": { "message": { "type": "string" } },
          "required": ["message"]
        }
      },
      "required": ["type", "error"]
    },
    {
      "description": "Item started - contains full item object with id",
      "properties": {
        "type": { "const": "item.started" },
        "item": { "$ref": "#/$defs/Item" }
      },
      "required": ["type", "item"]
    },
    {
      "description": "Item updated - streaming updates",
      "properties": {
        "type": { "const": "item.updated" },
        "item": { "$ref": "#/$defs/Item" }
      },
      "required": ["type", "item"]
    },
    {
      "description": "Item completed with status",
      "properties": {
        "type": { "const": "item.completed" },
        "item": { "$ref": "#/$defs/Item" }
      },
      "required": ["type", "item"]
    },
    {
      "description": "Error event",
      "properties": {
        "type": { "const": "error" },
        "message": { "type": "string" }
      },
      "required": ["type", "message"]
    }
  ]
}
```

#### Gemini CLI Event Schema
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://agent-protocol.dev/schemas/gemini-event.json",
  "title": "GeminiStreamEvent",
  "oneOf": [
    {
      "description": "Session initialization event (first event emitted)",
      "properties": {
        "type": { "const": "init" },
        "timestamp": { "type": "string", "format": "date-time" },
        "session_id": { "type": "string" },
        "model": { "type": "string" }
      },
      "required": ["type", "session_id"]
    },
    {
      "description": "User or assistant message",
      "properties": {
        "type": { "const": "message" },
        "timestamp": { "type": "string", "format": "date-time" },
        "role": { "enum": ["user", "assistant"] },
        "content": { "type": "string" },
        "delta": { "type": "boolean" }
      },
      "required": ["type", "role", "content"]
    },
    {
      "description": "Tool invocation request",
      "properties": {
        "type": { "const": "tool_use" },
        "timestamp": { "type": "string", "format": "date-time" },
        "tool_name": { "type": "string" },
        "tool_id": { "type": "string" },
        "parameters": { "type": "object" }
      },
      "required": ["type", "tool_name", "tool_id"]
    },
    {
      "description": "Tool execution result",
      "properties": {
        "type": { "const": "tool_result" },
        "timestamp": { "type": "string", "format": "date-time" },
        "tool_id": { "type": "string" },
        "status": { "enum": ["success", "error"] },
        "output": { "type": "string" },
        "error": {
          "type": "object",
          "properties": {
            "type": { "type": "string" },
            "message": { "type": "string" }
          }
        }
      },
      "required": ["type", "tool_id", "status"]
    },
    {
      "description": "Session completion",
      "properties": {
        "type": { "const": "result" },
        "status": { "enum": ["success", "error"] },
        "stats": {
          "type": ["object", "null"],
          "properties": {
            "total_tokens": { "type": "integer" },
            "input_tokens": { "type": "integer" },
            "output_tokens": { "type": "integer" },
            "thought_tokens": { "type": "integer" },
            "cache_tokens": { "type": "integer" },
            "tool_tokens": { "type": "integer" },
            "duration_ms": { "type": "integer" },
            "tool_calls": { "type": "integer" }
          }
        },
        "timestamp": { "type": "string", "format": "date-time" },
        "error": { "type": "object" }
      },
      "required": ["type", "status"]
    },
    {
      "description": "Error event with severity",
      "properties": {
        "type": { "const": "error" },
        "timestamp": { "type": "string", "format": "date-time" },
        "severity": { "enum": ["warning", "error"] },
        "message": { "type": "string" }
      },
      "required": ["type", "severity", "message"]
    }
  ]
}
```

---

## 9. Implementation Notes

### 9.1 Dart Client Library Architecture

```
lib/
├── src/
│   ├── client/
│   │   ├── agent_client.dart       # Main unified client
│   │   ├── session.dart            # Session handle with event stream
│   │   └── config.dart             # SessionConfig and enums
│   ├── events/
│   │   ├── agent_event.dart        # Sealed event hierarchy
│   │   └── token_usage.dart        # TokenUsage model
│   ├── adapters/
│   │   ├── adapter.dart            # Base ProtocolAdapter
│   │   ├── claude_adapter.dart     # Claude event parsing
│   │   ├── codex_adapter.dart      # Codex event parsing
│   │   └── gemini_adapter.dart     # Gemini event parsing
│   ├── transport/
│   │   ├── stdio_transport.dart    # Process spawning & JSONL reading
│   │   └── jsonl_parser.dart       # Line-by-line JSON parsing
│   └── errors/
│       └── agent_error.dart        # Unified error types
└── agent_protocol.dart             # Public API exports
```

### 9.2 Usage Example

```dart
import 'package:agent_protocol/agent_protocol.dart';

Future<void> main() async {
  // Create unified client
  final client = AgentClient();

  // Start a Claude session
  final session = await client.startSession(
    SessionConfig(
      agentType: AgentType.claude,
      prompt: 'Refactor the authentication module to use async/await',
      workingDirectory: '/path/to/project',
      approvalMode: ApprovalMode.autoAll,  // YOLO mode
    ),
  );

  // Stream and process events
  await for (final event in session.events) {
    switch (event) {
      case SessionStartedEvent(:final sessionId):
        print('Session started: $sessionId');

      case TextChunkEvent(:final content, :final isPartial):
        stdout.write(content);
        if (!isPartial) print('');

      case ToolStartedEvent(:final toolName, :final arguments):
        print('\n[Tool] $toolName: $arguments');

      case ToolCompletedEvent(:final toolId, :final success, :final result):
        print('[Result] $toolId: ${success ? "OK" : "FAILED"} - $result');

      case FileChangedEvent(:final filePath, :final changeType):
        print('[File] $changeType: $filePath');

      case TurnCompletedEvent(:final usage):
        if (usage != null) {
          print('\n[Tokens] in=${usage.inputTokens} out=${usage.outputTokens}');
        }

      case SessionEndedEvent(:final reason, :final error):
        print('\n[End] $reason${error != null ? ": $error" : ""}');
    }
  }

  // Resume session later
  final resumed = await client.startSession(
    SessionConfig(
      agentType: AgentType.claude,
      prompt: 'Continue with error handling',
      sessionId: session.id,  // Resume this session
    ),
  );
}
```

### 9.3 StdioTransport Implementation

```dart
class StdioTransport {
  final String executable;
  final List<String> args;
  final String? workingDirectory;
  final Map<String, String>? environment;

  Process? _process;

  Stream<String> start() async* {
    _process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );

    // Stream stdout lines
    await for (final line in _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isNotEmpty && line.trim().startsWith('{')) {
        yield line;
      }
    }

    // Check exit code
    final exitCode = await _process!.exitCode;
    if (exitCode != 0) {
      final stderr = await _process!.stderr.transform(utf8.decoder).join();
      throw AgentError(
        AgentErrorType.processExitError,
        'Process exited with code $exitCode: $stderr',
      );
    }
  }

  Future<void> cancel() async {
    _process?.kill(ProcessSignal.sigterm);
  }
}
```

### 9.4 Error Handling

```dart
enum AgentErrorType {
  processSpawnFailed,
  processExitError,
  jsonParseError,
  protocolError,
  permissionDenied,
  sessionNotFound,
  timeout,
  unknown,
}

class AgentError implements Exception {
  final AgentErrorType type;
  final String message;
  final String? nativeError;
  final AgentType? agentType;
  final int? exitCode;

  @override
  String toString() => 'AgentError($type): $message';
}
```

### 9.5 Testing with Mock Streams

```dart
class MockTransport {
  final List<String> events;

  Stream<String> start() async* {
    for (final event in events) {
      yield event;
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }
}

void main() {
  test('Claude adapter parses tool_use correctly', () async {
    final adapter = ClaudeAdapter();
    final mockEvents = [
      '{"type":"init","session_id":"sess_123"}',
      '{"type":"tool_use","id":"toolu_01","name":"Edit","input":{"file":"test.txt"}}',
      '{"type":"tool_result","tool_use_id":"toolu_01","content":"OK","is_error":false}',
      '{"type":"result","status":"success","session_id":"sess_123"}',
    ];

    final events = mockEvents.map(adapter.parseEvent).whereType<AgentEvent>().toList();

    expect(events[0], isA<SessionStartedEvent>());
    expect(events[1], isA<ToolStartedEvent>());
    expect((events[1] as ToolStartedEvent).toolName, equals('Edit'));
    expect(events[2], isA<ToolCompletedEvent>());
    expect(events[3], isA<SessionEndedEvent>());
  });
}
```

---

## Appendix A: CLI Installation

```bash
# Claude Code
npm install -g @anthropic-ai/claude-code

# Codex CLI
npm install -g @openai/codex
# OR
curl -fsSL https://codex.openai.com/install.sh | sh

# Gemini CLI
npm install -g @google/gemini-cli
# OR
npx @google/gemini-cli
```

## Appendix B: Environment Variables

| Variable    | Claude              | Codex            | Gemini                              |
| ----------- | ------------------- | ---------------- | ----------------------------------- |
| **API Key** | `ANTHROPIC_API_KEY` | `OPENAI_API_KEY` | `GEMINI_API_KEY` / `GOOGLE_API_KEY` |
| **Model**   | `CLAUDE_MODEL`      | -                | `GEMINI_MODEL`                      |
| **Debug**   | `CLAUDE_DEBUG=1`    | -                | `-d` flag                           |

## Appendix C: References

- [Claude Code CLI Reference](https://code.claude.com/docs/en/cli-reference)
- [Codex CLI Documentation](https://github.com/openai/codex/tree/main/docs)
- [Gemini CLI Documentation](https://geminicli.com/docs/)
- [Claude Agent SDK](https://platform.claude.com/docs/en/agent-sdk/overview)
- [Stream-JSON
  Chaining](https://github.com/ruvnet/claude-flow/wiki/Stream-Chaining)

---

*End of Specification v3.1.0*
