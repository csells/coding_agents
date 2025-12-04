# CLI Agent Streaming Protocol Specification

**Version:** 4.0.0
**Date:** December 3, 2025
**Purpose:** Comprehensive specification of headless stdio/JSONL streaming protocols for Claude Code, Codex CLI, and Gemini CLI with a unified abstraction layer for Dart client library implementation.

> **Changelog v4.0.0:** Clarified multi-turn architecture patterns - all three CLIs support disk-based session persistence and resume. Updated invocation patterns for Codex and Gemini headless modes with resume capability.
>
> **Changelog v3.0.0:** Complete event catalog documentation for all CLIs, permission request/response flow documentation, comprehensive event type comparison matrix.

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

All three major AI coding CLI agents support **headless operation via stdio with JSONL (newline-delimited JSON) streaming output**. This specification documents the native streaming protocols.

| CLI | Headless Command | Output Flag | Message Format |
|-----|------------------|-------------|----------------|
| **Claude Code** | `claude -p "prompt"` | `--output-format stream-json` | JSONL |
| **Codex CLI** | `codex exec "prompt"` | `--output-jsonl` | JSONL |
| **Gemini CLI** | `gemini -p "prompt"` | `--output-format stream-json` | JSONL |

### Multi-Turn Architecture Comparison

All three CLIs support **multi-turn conversations with session persistence**, but use different architectural patterns:

| CLI | Process Model | Session Persistence | Multi-Turn Pattern | Session Storage |
|-----|---------------|--------------------|--------------------|-----------------|
| **Claude Code** | Long-lived (bidirectional JSONL) | Disk | Send messages to same process via stdin | `~/.claude/sessions/` |
| **Codex CLI** | Process-per-turn | Disk | Spawn new process with `resume <thread_id>` | `~/.codex/sessions/` |
| **Gemini CLI** | Process-per-turn | Disk | Spawn new process with `--resume <session_id>` | `~/.gemini/tmp/<project>/chats/` |

**Key insight:** Codex and Gemini use the **same architectural pattern** - spawn a new CLI process for each user turn, with session state persisted to disk and restored via resume flags. Claude Code is unique in supporting true bidirectional JSONL streaming within a single long-lived process.

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

| Argument | Short | Description |
|----------|-------|-------------|
| `--print` | `-p` | Non-interactive/headless mode |
| `--output-format <fmt>` | | `text`, `json`, or `stream-json` |
| `--input-format <fmt>` | | `text` or `stream-json` |
| `--include-partial-messages` | | Include streaming deltas |
| `--continue` | `-c` | Resume most recent session |
| `--resume <id>` | `-r` | Resume specific session |
| `--dangerously-skip-permissions` | | Auto-approve all tools (YOLO) |
| `--allowedTools <list>` | | Tools to auto-approve |
| `--disallowedTools <list>` | | Tools to block |
| `--permission-mode <mode>` | | Permission mode (e.g., `plan`) |
| `--permission-prompt-tool <tool>` | | MCP tool for permission prompts |
| `--max-turns <n>` | | Limit agentic turns |
| `--model <model>` | | Model selection |
| `--system-prompt <text>` | | Replace system prompt |
| `--append-system-prompt <text>` | | Add to system prompt |
| `--verbose` | | Detailed turn-by-turn output |
| `--json-schema <schema>` | | Validate output against schema |

### 3.3 Input Format (stdin)

Claude Code supports **continuous JSONL streaming** via stdin when using `--input-format stream-json`. This enables true multi-turn conversations within a single process.

**Invocation for continuous streaming:**
```bash
claude --output-format stream-json --input-format stream-json
```

**Input Message Schema:**

User message (send follow-up prompts):
```json
{"type":"message","role":"user","content":[{"type":"text","text":"Your follow-up message here"}]}
```

The input format mirrors the output message format. Each line must be a complete JSON object.

**Multi-turn Flow:**
1. Spawn process with `--output-format stream-json --input-format stream-json`
2. Write initial prompt as JSONL to stdin
3. Read JSONL events from stdout (init, message, tool_use, tool_result, etc.)
4. When assistant completes a response, write next user message to stdin
5. Continue until session ends or process is terminated

**Input Message Types:**

| Type | Purpose | Schema |
|------|---------|--------|
| `message` | User follow-up | `{"type":"message","role":"user","content":[{"type":"text","text":"..."}]}` |

**Note:** Unlike Codex and Gemini CLIs, Claude Code maintains a persistent connection. Do NOT close stdin after the initial prompt if you intend to send follow-up messages.

### 3.4 Event Types

```typescript
type ClaudeStreamEventType =
  | "init"         // Session initialization with session_id
  | "message"      // Assistant or user message content
  | "tool_use"     // Tool invocation request
  | "tool_result"  // Tool execution result
  | "result"       // Session completion status
  | "error"        // Error occurred
  | "system"       // System event (multiple subtypes)
  | "stream_event" // Raw API streaming delta (--verbose mode only)

// System event subtypes
type ClaudeSystemSubtype =
  | "init"             // System initialization info
  | "compact_boundary" // Context compaction marker

// Message content block types
type ClaudeContentBlockType =
  | "text"      // Plain text content
  | "tool_use"  // Inline tool use reference

// Result status values
type ClaudeResultStatus =
  | "success"   // Completed successfully
  | "error"     // Completed with error
  | "cancelled" // User cancelled
```

### 3.4 Event Schemas

#### Init Event
```json
{
  "type": "init",
  "session_id": "sess_abc123",
  "timestamp": "2025-12-03T10:00:00.000Z"
}
```

#### Message Event (Assistant)
```json
{
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "I'll help you refactor the authentication module..."
    }
  ]
}
```

#### Message Event (Partial/Streaming)
```json
{
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "I'll help"
    }
  ],
  "partial": true
}
```

#### Tool Use Event
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
```json
{
  "type": "tool_result",
  "tool_use_id": "toolu_01ABC123",
  "content": "File updated successfully",
  "is_error": false
}
```

#### Result Event
```json
{
  "type": "result",
  "status": "success",
  "session_id": "sess_abc123",
  "duration_ms": 5000
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

#### System Event (Init Subtype)
```json
{
  "type": "system",
  "subtype": "init",
  "version": "1.0.32",
  "cwd": "/path/to/project",
  "tools": ["Read", "Edit", "Write", "Bash", "Glob", "Grep"]
}
```

#### System Event (Compact Boundary Subtype)
```json
{
  "type": "system",
  "subtype": "compact_boundary",
  "compact_metadata": {
    "trigger": "auto",
    "pre_tokens": 50000,
    "post_tokens": 25000,
    "summary_tokens": 500
  }
}
```

#### Stream Event (Verbose Mode Only)
When `--verbose` flag is enabled, raw API streaming deltas are exposed:
```json
{
  "type": "stream_event",
  "event_type": "content_block_delta",
  "index": 0,
  "delta": {
    "type": "text_delta",
    "text": "I'll"
  }
}
```

```json
{
  "type": "stream_event",
  "event_type": "message_stop"
}
```

### 3.5 Complete Event Flow Example

```jsonl
{"type":"init","session_id":"sess_abc123","timestamp":"2025-12-03T10:00:00.000Z"}
{"type":"message","role":"assistant","content":[{"type":"text","text":"I'll analyze the codebase..."}]}
{"type":"tool_use","id":"toolu_01","name":"Read","input":{"file_path":"/src/auth.ts"}}
{"type":"tool_result","tool_use_id":"toolu_01","content":"export function login()...","is_error":false}
{"type":"message","role":"assistant","content":[{"type":"text","text":"I found the auth module. Let me refactor it..."}]}
{"type":"tool_use","id":"toolu_02","name":"Edit","input":{"file_path":"/src/auth.ts","old_string":"function login()","new_string":"async function login()"}}
{"type":"tool_result","tool_use_id":"toolu_02","content":"File updated","is_error":false}
{"type":"message","role":"assistant","content":[{"type":"text","text":"Done! I've made the login function async."}]}
{"type":"result","status":"success","session_id":"sess_abc123","duration_ms":12500}
```

### 3.6 Permission Control

| Mode | Flag | Behavior |
|------|------|----------|
| Default (ask) | (none) | Prompt for each tool |
| YOLO | `--dangerously-skip-permissions` | Auto-approve all |
| Allowlist | `--allowedTools "Read,Edit"` | Auto-approve listed tools |
| Blocklist | `--disallowedTools "Bash"` | Block listed tools |
| Plan mode | `--permission-mode plan` | Planning only |
| MCP Delegate | `--permission-prompt-tool <tool>` | Delegate to MCP tool |

**Tool format examples:**
```bash
--allowedTools "Bash(git log:*)" "Bash(git diff:*)" "Read" "Edit"
```

### 3.7 Permission Prompt Tool (MCP Delegation)

For headless orchestration, Claude Code supports delegating permission prompts to an external MCP tool via `--permission-prompt-tool <mcp_server_name>__<tool_name>`.

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

**Behavior values:**
| Value | Description |
|-------|-------------|
| `"allow"` | Permit the tool execution |
| `"deny"` | Block the tool execution |
| `"allowAlways"` | Allow this tool for remainder of session |
| `"denyAlways"` | Deny this tool for remainder of session |

**Note:** When using `--permission-prompt-tool`, no permission events are emitted in the stream. The permission flow is handled entirely through the MCP tool call mechanism. The orchestrating client must implement the MCP server with the permission handling tool.

### 3.8 Session Management

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

---

## 4. Codex CLI Protocol

### 4.1 Invocation

**Basic headless execution:**
```bash
codex exec --output-jsonl "Your prompt here"
```

**Resume session:**
```bash
codex exec --output-jsonl --resume sess_abc123 "Continue with..."
codex resume --last  # Interactive resume
codex resume sess_abc123  # Resume specific
```

**Full auto mode:**
```bash
codex exec --output-jsonl --full-auto "Your prompt"
```

### 4.2 CLI Arguments

| Argument | Short | Description |
|----------|-------|-------------|
| `exec` | | Non-interactive mode subcommand |
| `--output-jsonl` | | Enable JSONL streaming |
| `--output-last-message` | `-o` | Output only final message |
| `--output-schema <file>` | | JSON schema for structured output |
| `--ask-for-approval` | `-a` | Require approval (untrusted mode) |
| `--full-auto` | | Auto-approve all (danger mode) |
| `--model <name>` | | Model selection |
| `--cd <path>` | | Working directory |
| `--env KEY=val` | | Set environment variable |
| `resume` | | Resume session subcommand |
| `--last` | | Resume most recent session |

### 4.3 Input Format (stdin)

Codex CLI does **NOT** support continuous JSONL input streaming. Each invocation processes a single prompt.

**Input mechanism:**
- Prompt is passed as a command-line argument to `codex exec`
- Stdin is written with the prompt string, then **immediately closed**
- For multi-turn, spawn a new process with `--resume <session_id>`

**Single-turn flow:**
```bash
codex exec --output-jsonl "Your prompt here"
```

**Multi-turn flow (process-per-turn):**
```bash
# Turn 1: Initial prompt
codex exec --output-jsonl "Analyze the auth module"
# Output includes thread_id in thread.started event

# Turn 2: Resume with follow-up
codex exec --output-jsonl --resume <thread_id> "Now refactor it"

# Turn 3: Continue
codex exec --output-jsonl --resume <thread_id> "Add tests"
```

**Key difference from Claude Code:** Codex requires a new process for each turn. The session state is persisted to disk (`~/.codex/sessions/`) and restored via `--resume`.

### 4.4 Event Types

```typescript
type CodexEventType =
  // Session lifecycle
  | "thread.started"
  // Turn lifecycle
  | "turn.started"
  | "turn.completed"
  | "turn.failed"
  // Item lifecycle
  | "item.started"
  | "item.updated"
  | "item.completed"
  // Errors
  | "error"
```

### 4.4 Item Types

```typescript
type CodexItemType =
  | "agent_message"      // Model text response (assistant output)
  | "reasoning"          // Internal chain-of-thought reasoning
  | "command_execution"  // Shell command execution
  | "file_change"        // File create/modify/delete
  | "mcp_tool_call"      // MCP tool invocation
  | "web_search"         // Web search query and results
  | "todo_list"          // Task planning list
  | "error"              // Error during item processing

// Item status values
type CodexItemStatus =
  | "success"  // Item completed successfully
  | "failed"   // Item execution failed
  | "skipped"  // Item was skipped
```

### 4.5 Event Schemas

#### Thread Started
```json
{
  "type": "thread.started",
  "thread_id": "sess_abc123xyz"
}
```

#### Turn Started
```json
{
  "type": "turn.started"
}
```

#### Item Started
```json
{
  "type": "item.started",
  "item_type": "agent_message"
}
```

#### Item Updated (Agent Message)
```json
{
  "type": "item.updated",
  "item_type": "agent_message",
  "content": "I'll help you refactor..."
}
```

#### Item Updated (Command Execution)
```json
{
  "type": "item.updated",
  "item_type": "command_execution",
  "command_line": "npm test",
  "aggregated_output": "[PASS] auth.test.js\n[PASS] user.test.js\n"
}
```

#### Item Updated (File Change)
```json
{
  "type": "item.updated",
  "item_type": "file_change",
  "changes": [
    {
      "path": "src/auth.ts",
      "before": "function login() {",
      "after": "async function login() {"
    }
  ]
}
```

#### Item Updated (MCP Tool Call)
```json
{
  "type": "item.updated",
  "item_type": "mcp_tool_call",
  "tool_name": "database_query",
  "tool_input": {"sql": "SELECT * FROM users"},
  "tool_result": "[{\"id\":1,\"name\":\"Alice\"}]"
}
```

#### Item Updated (Reasoning)
Internal chain-of-thought reasoning (visible in output):
```json
{
  "type": "item.updated",
  "item_type": "reasoning",
  "reasoning": "I need to analyze the authentication flow. First, let me check the login function...",
  "summary": "Analyzing authentication flow"
}
```

#### Item Updated (Web Search)
```json
{
  "type": "item.updated",
  "item_type": "web_search",
  "query": "typescript async await best practices 2025",
  "results": [
    {
      "title": "Async/Await Best Practices",
      "url": "https://example.com/article",
      "snippet": "Modern TypeScript async patterns..."
    }
  ]
}
```

#### Item Updated (Todo List)
```json
{
  "type": "item.updated",
  "item_type": "todo_list",
  "items": [
    {"id": "1", "task": "Analyze current auth implementation", "status": "completed"},
    {"id": "2", "task": "Refactor to async/await", "status": "in_progress"},
    {"id": "3", "task": "Update tests", "status": "pending"}
  ]
}
```

#### Item Updated (Error)
```json
{
  "type": "item.updated",
  "item_type": "error",
  "error_type": "execution_failed",
  "message": "Command exited with non-zero status",
  "details": {
    "command": "npm test",
    "exit_code": 1,
    "stderr": "Error: Test failed..."
  }
}
```

#### Item Completed
```json
{
  "type": "item.completed",
  "item_type": "command_execution",
  "status": "success",
  "exit_code": 0
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

### 4.6 Complete Event Flow Example

```jsonl
{"type":"thread.started","thread_id":"sess_abc123"}
{"type":"turn.started"}
{"type":"item.started","item_type":"reasoning"}
{"type":"item.updated","item_type":"reasoning","reasoning":"I need to analyze the auth module first..."}
{"type":"item.completed","item_type":"reasoning","status":"success"}
{"type":"item.started","item_type":"command_execution"}
{"type":"item.updated","item_type":"command_execution","command_line":"cat src/auth.ts","aggregated_output":""}
{"type":"item.updated","item_type":"command_execution","command_line":"cat src/auth.ts","aggregated_output":"export function login() {..."}
{"type":"item.completed","item_type":"command_execution","status":"success","exit_code":0}
{"type":"item.started","item_type":"file_change"}
{"type":"item.updated","item_type":"file_change","changes":[{"path":"src/auth.ts","before":"function login()","after":"async function login()"}]}
{"type":"item.completed","item_type":"file_change","status":"success"}
{"type":"item.started","item_type":"agent_message"}
{"type":"item.updated","item_type":"agent_message","content":"I've refactored the login function to be async."}
{"type":"item.completed","item_type":"agent_message","status":"success"}
{"type":"turn.completed","usage":{"input_tokens":1250,"output_tokens":487}}
```

### 4.7 Permission Control

**Approval Policies:**

| Mode | Flag | Config Value | Behavior |
|------|------|--------------|----------|
| Untrusted | `-a` | `untrusted` | Prompt for sensitive commands |
| On-request | (default) | `on-request` | Prompt on escalation |
| On-failure | | `on-failure` | Prompt if sandbox blocks |
| Full auto | `--full-auto` | `never` | No prompts |

**Sandbox Modes:**

| Mode | Config Value | Write | Network |
|------|--------------|-------|---------|
| Read-only | `read-only` | No | No |
| Workspace | `workspace-write` | CWD + tmp | No |
| Full access | `danger-full-access` | All | Yes |

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

Unlike Claude Code, Codex CLI does **not** emit explicit permission request/response events in the stream. Permission handling is pre-configured via:
1. Command-line flags (`--full-auto`, `-a`)
2. Configuration file (`~/.codex/config.toml`)
3. Sandbox enforcement (blocks disallowed operations)

For fully headless operation, use `--full-auto` to skip all permission prompts. For security-conscious automation, use sandbox modes to restrict capabilities instead of relying on runtime approval.

### 4.8 Session Storage

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

| Argument | Short | Description |
|----------|-------|-------------|
| `--prompt <text>` | `-p` | Headless mode with prompt |
| `--output-format <fmt>` | | `text`, `json`, or `stream-json` |
| `--approval-mode <mode>` | | `default`, `auto_edit`, or `yolo` |
| `--yolo` | `-y` | Auto-approve all |
| `--auto-edit` | | Auto-approve file edits only |
| `--sandbox` | | Enable Docker sandbox |
| `--sandbox-image <img>` | | Custom sandbox image |
| `--model <name>` | `-m` | Model selection |
| `--resume` | | Resume session |
| `--allowed-tools <list>` | | Tool allowlist |
| `--debug` | `-d` | Enable debug output |

### 5.3 Input Format (stdin)

Gemini CLI uses the **same process-per-turn architecture as Codex CLI**. Each invocation processes a single prompt, and multi-turn conversations require spawning new processes with the `--resume` flag.

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

| Aspect | Codex CLI | Gemini CLI |
|--------|-----------|------------|
| Process model | Process-per-turn | Process-per-turn |
| Session persistence | `~/.codex/sessions/` | `~/.gemini/tmp/<project>/chats/` |
| Resume flag | `resume <thread_id>` | `--resume <session_id>` |
| Session ID source | `thread.started` event | `init` event |
| Stdin format | Plain text | Plain text |
| Output format | JSONL (`--output-jsonl`) | JSONL (`--output-format stream-json`) |

**Key difference from Claude Code:** Both Codex and Gemini require a new process for each user turn, with session state persisted to disk and restored via resume flags. Claude Code is unique in supporting true bidirectional JSONL streaming within a single long-lived process.

### 5.4 Event Types

```typescript
type GeminiStreamEventType =
  | "init"        // Session initialization with session_id and model
  | "message"     // User/assistant message
  | "tool_use"    // Tool invocation request
  | "tool_result" // Tool execution result
  | "content"     // Text content from model (streaming chunks) - legacy
  | "tool_call"   // Tool invocation (atomic) - legacy
  | "result"      // Session completion with stats
  | "error"       // Error event
  | "retry"       // Retry signal on transient failure

// Result status values
type GeminiResultStatus =
  | "success"    // Completed successfully
  | "error"      // Completed with error
  | "cancelled"  // User cancelled

// Error codes
type GeminiErrorCode =
  | "INVALID_CHUNK"     // Malformed stream data
  | "EXECUTION_FAILED"  // Tool execution failed
  | "TIMEOUT"           // Operation timed out
  | "API_ERROR"         // Backend API error
  | "RATE_LIMIT"        // Rate limit exceeded
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

#### Content Event (legacy format, still supported)
```json
{
  "type": "content",
  "value": "I'll analyze the codebase structure..."
}
```

#### Tool Call Event (legacy format, still supported)
```json
{
  "type": "tool_call",
  "name": "write_file",
  "args": {
    "file_path": "./src/auth.ts",
    "content": "export async function login() { ... }"
  }
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
  "status": "error",
  "error": {
    "code": "INVALID_CHUNK",
    "message": "Stream ended with invalid chunk or missing finish reason"
  }
}
```

#### Retry Event
```json
{
  "type": "retry",
  "attempt": 2,
  "max_attempts": 3,
  "delay_ms": 1000
}
```

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

**Note:** The `session_id` from the `init` event (`abc123-def456`) can be used to resume this session:
```bash
gemini --resume abc123-def456 -p "Add tests for the login function" --output-format stream-json
```

### 5.7 Permission Control

**Approval Modes:**

| Mode | Flag | Behavior |
|------|------|----------|
| Default | (none) | Prompt for each tool |
| Auto-edit | `--auto-edit` | Auto-approve file edits only |
| YOLO | `-y` / `--yolo` | Auto-approve everything |

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

Gemini CLI does **not** emit explicit permission request/response events in the stream. Like Codex, permissions are pre-configured via:
1. Command-line flags (`-y`, `--auto-edit`, `--approval-mode`)
2. Settings file trust configuration
3. Tool include/exclude lists

For fully headless operation, use `-y` (yolo) mode to auto-approve all operations. There is no MCP-based permission delegation mechanism like Claude Code's `--permission-prompt-tool`.

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

| Action | Claude Code | Codex CLI | Gemini CLI |
|--------|-------------|-----------|------------|
| **Headless** | `claude -p "prompt"` | `codex exec "prompt"` | `gemini -p "prompt"` |
| **Stream JSON** | `--output-format stream-json` | `--output-jsonl` | `--output-format stream-json` |
| **Resume** | `--resume <id>` or `-c` | `--resume <id>` or `resume --last` | `--resume` or `--resume <id>` |
| **YOLO** | `--dangerously-skip-permissions` | `--full-auto` | `-y` / `--yolo` |
| **Allowlist** | `--allowedTools "Tool1,Tool2"` | (config only) | `--allowed-tools "tool1,tool2"` |

### 6.2 Complete Event Type Catalog

#### Claude Code Events (8 types)

| Event Type | Purpose | Fields | Notes |
|------------|---------|--------|-------|
| `init` | Session initialization | `session_id`, `timestamp` | First event emitted |
| `message` | Text content | `role`, `content[]`, `partial?` | Supports partial streaming |
| `tool_use` | Tool invocation request | `id`, `name`, `input` | Before tool executes |
| `tool_result` | Tool execution result | `tool_use_id`, `content`, `is_error` | After tool completes |
| `result` | Session completion | `status`, `session_id`, `duration_ms` | Final event |
| `error` | Error occurred | `error.type`, `error.message` | May occur any time |
| `system` | System event | `subtype`, varies by subtype | Subtypes: `init`, `compact_boundary` |
| `stream_event` | Raw API delta | `event_type`, `delta`, `index` | Only with `--verbose` |

#### Codex CLI Events (8 types + 8 item types)

**Session/Turn Events:**

| Event Type | Purpose | Fields | Notes |
|------------|---------|--------|-------|
| `thread.started` | Session start | `thread_id` | First event emitted |
| `turn.started` | Turn lifecycle start | (none) | Before items |
| `turn.completed` | Turn lifecycle end | `usage` | Contains token counts |
| `turn.failed` | Turn failure | `error.message` | On unrecoverable error |
| `error` | Session-level error | `message` | May occur any time |

**Item Lifecycle Events:**

| Event Type | Purpose | Fields | Notes |
|------------|---------|--------|-------|
| `item.started` | Item begins | `item_type` | Start of item processing |
| `item.updated` | Item progress | `item_type`, varies | Streaming updates |
| `item.completed` | Item finished | `item_type`, `status` | End of item processing |

**Item Types (8):**

| Item Type | Purpose | Key Fields in `item.updated` |
|-----------|---------|------------------------------|
| `agent_message` | Assistant text | `content` |
| `reasoning` | Chain-of-thought | `reasoning`, `summary` |
| `command_execution` | Shell command | `command_line`, `aggregated_output` |
| `file_change` | File modification | `changes[]` with `path`, `before`, `after` |
| `mcp_tool_call` | MCP tool | `tool_name`, `tool_input`, `tool_result` |
| `web_search` | Web search | `query`, `results[]` |
| `todo_list` | Task planning | `items[]` with `task`, `status` |
| `error` | Error item | `error_type`, `message`, `details` |

#### Gemini CLI Events (9 types)

| Event Type | Purpose | Fields | Notes |
|------------|---------|--------|-------|
| `init` | Session start | `session_id`, `model`, `timestamp` | First event, contains session ID for resume |
| `message` | User/assistant message | `role`, `content`, `delta?`, `timestamp` | Supports streaming via delta flag |
| `tool_use` | Tool invocation request | `tool_name`, `tool_id`, `parameters`, `timestamp` | Before tool executes |
| `tool_result` | Tool execution result | `tool_id`, `status`, `output?`, `error?`, `timestamp` | After tool completes |
| `content` | Text content (legacy) | `value` | Streaming text chunks |
| `tool_call` | Tool invocation (legacy) | `name`, `args` | Atomic (no separate result) |
| `result` | Session completion | `status`, `stats`, `timestamp`, `error?` | Final event |
| `error` | Error event | `error.code`, `error.message` | May occur any time |
| `retry` | Retry signal | `attempt`, `max_attempts`, `delay_ms` | On transient failure |

### 6.3 Comprehensive Event Mapping Matrix

This matrix maps every event type across all three CLIs:

| Semantic Concept | Claude Code | Codex CLI | Gemini CLI |
|------------------|-------------|-----------|------------|
| **Session Lifecycle** | | | |
| Session start | `init` | `thread.started` | `init` |
| Session end (success) | `result` (status: success) | (process exit 0) | `result` (status: success) |
| Session end (error) | `result` (status: error) | `turn.failed` | `result` (status: error) |
| Session end (cancelled) | `result` (status: cancelled) | (SIGTERM) | `result` (status: cancelled) |
| **Turn Lifecycle** | | | |
| Turn start | (implicit) | `turn.started` | (implicit) |
| Turn end | (implicit) | `turn.completed` | (implicit in result) |
| Turn failed | `error` | `turn.failed` | `error` |
| **Content Events** | | | |
| Assistant text (complete) | `message` (partial: false) | `item.completed` (agent_message) | `content` (final) |
| Assistant text (streaming) | `message` (partial: true) | `item.updated` (agent_message) | `content` (incremental) |
| User message | `message` (role: user) | - | - |
| **Tool Lifecycle** | | | |
| Tool invocation start | `tool_use` | `item.started` (command/mcp/file) | `tool_call` |
| Tool progress/output | - | `item.updated` | - |
| Tool completed (success) | `tool_result` (is_error: false) | `item.completed` (status: success) | (implicit in next content) |
| Tool completed (error) | `tool_result` (is_error: true) | `item.completed` (status: failed) | (error in result) |
| **Specific Tool Types** | | | |
| Shell command | `tool_use` (name: Bash) | `item.*` (command_execution) | `tool_call` (name: run_shell) |
| File read | `tool_use` (name: Read) | `item.*` (command_execution) | `tool_call` (name: read_file) |
| File write/edit | `tool_use` (name: Edit/Write) | `item.*` (file_change) | `tool_call` (name: write_file) |
| MCP tool | `tool_use` (name: mcp__*) | `item.*` (mcp_tool_call) | `tool_call` (MCP name) |
| Web search | `tool_use` (name: WebSearch) | `item.*` (web_search) | `tool_call` (name: google_search) |
| **Reasoning/Thinking** | | | |
| Visible reasoning | - | `item.*` (reasoning) | - |
| Internal thinking | (not exposed) | (summary in reasoning) | (not exposed) |
| **Task Management** | | | |
| Todo list | `tool_use` (name: TodoWrite) | `item.*` (todo_list) | - |
| **System Events** | | | |
| System init info | `system` (subtype: init) | - | - |
| Context compaction | `system` (subtype: compact_boundary) | - | - |
| Verbose/debug | `stream_event` (--verbose) | - | (--debug to stderr) |
| **Error Handling** | | | |
| Session error | `error` | `error` | `error` |
| Tool error | `tool_result` (is_error: true) | `item.*` (error item_type) | `result` (status: error) |
| Retry signal | - | - | `retry` |
| **Token/Usage Tracking** | | | |
| Per-turn usage | - | `turn.completed.usage` | - |
| Final usage | `result.duration_ms` | `turn.completed.usage` | `result.stats` |
| **Permission Events** | | | |
| Permission request | (via MCP tool call) | - | - |
| Permission response | (via MCP tool result) | - | - |

### 6.4 Permission Mode Mapping

| Behavior | Claude Code | Codex CLI | Gemini CLI |
|----------|-------------|-----------|------------|
| **Ask for all** | Default | `untrusted` / `-a` | `default` |
| **Ask dangerous only** | (via hooks) | `on-request` | - |
| **Auto file edits** | `--allowedTools "Edit,Write"` | - | `auto_edit` |
| **Auto all** | `--dangerously-skip-permissions` | `--full-auto` | `--yolo` |
| **Sandbox** | - | `workspace-write` | `--sandbox` |
| **MCP Permission Delegation** | `--permission-prompt-tool` | - | - |

### 6.5 Feature Comparison

| Feature | Claude Code | Codex CLI | Gemini CLI |
|---------|-------------|-----------|------------|
| **Streaming granularity** | Per-message | Per-item-update | Per-content-chunk |
| **Tool lifecycle events** | 2 (use/result) | 3 (start/update/complete) | 1 (atomic call) |
| **Reasoning visibility** | No | Yes (`reasoning` item) | No |
| **Token tracking** | No | Yes (turn.completed.usage) | Yes (result.stats) |
| **Structured output** | `--json-schema` | `--output-schema` | No |
| **Partial streaming** | `--include-partial-messages` | Built-in (item.updated) | Built-in |
| **MCP integration** | Yes | Yes | Yes |
| **Git checkpointing** | No | No | Yes |
| **Permission delegation** | MCP tool | Config only | Config only |

### 6.6 Event Flow Patterns

**Claude Code:**
```
init → message* → (tool_use → tool_result)* → message* → result
```

**Codex CLI:**
```
thread.started → turn.started →
  (item.started → item.updated* → item.completed)* →
turn.completed
```

**Gemini CLI:**
```
init → message* → (tool_use → tool_result)* → message* → result
```

**Note:** Gemini CLI's event flow pattern is now nearly identical to Claude Code's. The key difference is the process lifecycle: Claude Code maintains a long-lived bidirectional process, while Gemini uses process-per-turn with session persistence (like Codex).

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
| Native Event | Unified Event(s) |
|--------------|------------------|
| `type: "init"` | `SessionStartedEvent` |
| `type: "message"` | `TextChunkEvent` |
| `type: "message"` (partial: true) | `TextChunkEvent` (isPartial: true) |
| `type: "tool_use"` | `ToolStartedEvent` |
| `type: "tool_result"` | `ToolCompletedEvent` |
| `type: "result"` (success) | `SessionEndedEvent(completed)` |
| `type: "result"` (error) | `SessionEndedEvent(failed)` |
| `type: "error"` | `SessionEndedEvent(failed)` |
| `type: "system"` (subtype: init) | `SystemEvent` (informational, usually ignored) |
| `type: "system"` (subtype: compact_boundary) | `SystemEvent` (context management) |
| `type: "stream_event"` | `RawDeltaEvent` (verbose mode only) |

#### From Codex CLI
| Native Event | Unified Event(s) |
|--------------|------------------|
| `thread.started` | `SessionStartedEvent` |
| `turn.started` | `TurnStartedEvent` (optional) |
| `item.started` (agent_message) | `TextChunkEvent` (start) |
| `item.updated` (agent_message) | `TextChunkEvent` (streaming) |
| `item.completed` (agent_message) | `TextChunkEvent` (final) |
| `item.started` (reasoning) | `ReasoningEvent` (start) |
| `item.updated` (reasoning) | `ReasoningEvent` (streaming) |
| `item.completed` (reasoning) | `ReasoningEvent` (final) |
| `item.started` (command_execution) | `ToolStartedEvent` (shell) |
| `item.updated` (command_execution) | `ToolProgressEvent` (output streaming) |
| `item.completed` (command_execution) | `ToolCompletedEvent` (shell) |
| `item.started` (file_change) | `FileChangedEvent` (start) |
| `item.updated` (file_change) | `FileChangedEvent` (diff details) |
| `item.completed` (file_change) | `FileChangedEvent` (final) |
| `item.started` (mcp_tool_call) | `ToolStartedEvent` (MCP) |
| `item.updated` (mcp_tool_call) | `ToolProgressEvent` (MCP) |
| `item.completed` (mcp_tool_call) | `ToolCompletedEvent` (MCP) |
| `item.started` (web_search) | `ToolStartedEvent` (search) |
| `item.updated` (web_search) | `ToolProgressEvent` (results) |
| `item.completed` (web_search) | `ToolCompletedEvent` (search) |
| `item.*` (todo_list) | `TodoListEvent` |
| `item.*` (error) | `ErrorEvent` |
| `turn.completed` | `TurnCompletedEvent` |
| `turn.failed` | `SessionEndedEvent(failed)` |
| `error` | `SessionEndedEvent(failed)` |
| (process exit 0) | `SessionEndedEvent(completed)` |

#### From Gemini CLI
| Native Event | Unified Event(s) |
|--------------|------------------|
| `type: "init"` | `SessionStartedEvent` |
| `type: "message"` (role: user) | (informational, not translated) |
| `type: "message"` (role: assistant) | `TextChunkEvent` |
| `type: "message"` (delta: true) | `TextChunkEvent` (isPartial: true) |
| `type: "tool_use"` | `ToolStartedEvent` |
| `type: "tool_result"` (success) | `ToolCompletedEvent` |
| `type: "tool_result"` (error) | `ToolCompletedEvent` (success: false) |
| `type: "content"` (legacy) | `TextChunkEvent` |
| `type: "tool_call"` (legacy) | `ToolStartedEvent` + `ToolCompletedEvent` (atomic) |
| `type: "result"` (success) | `TurnCompletedEvent` + `SessionEndedEvent(completed)` |
| `type: "result"` (error) | `SessionEndedEvent(failed)` |
| `type: "result"` (cancelled) | `SessionEndedEvent(cancelled)` |
| `type: "error"` | `SessionEndedEvent(failed)` |
| `type: "retry"` | `RetryEvent` (transient failure handling) |

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
      "type": "object",
      "properties": {
        "type": { "const": "init" },
        "session_id": { "type": "string" },
        "timestamp": { "type": "string", "format": "date-time" }
      },
      "required": ["type", "session_id"]
    },
    {
      "type": "object",
      "properties": {
        "type": { "const": "message" },
        "role": { "enum": ["assistant", "user"] },
        "content": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "type": { "enum": ["text", "tool_use"] },
              "text": { "type": "string" }
            }
          }
        },
        "partial": { "type": "boolean" }
      },
      "required": ["type", "role", "content"]
    },
    {
      "type": "object",
      "properties": {
        "type": { "const": "tool_use" },
        "id": { "type": "string" },
        "name": { "type": "string" },
        "input": { "type": "object" }
      },
      "required": ["type", "id", "name", "input"]
    },
    {
      "type": "object",
      "properties": {
        "type": { "const": "tool_result" },
        "tool_use_id": { "type": "string" },
        "content": { "type": "string" },
        "is_error": { "type": "boolean" }
      },
      "required": ["type", "tool_use_id"]
    },
    {
      "type": "object",
      "properties": {
        "type": { "const": "result" },
        "status": { "enum": ["success", "error"] },
        "session_id": { "type": "string" },
        "duration_ms": { "type": "integer" }
      },
      "required": ["type", "status"]
    },
    {
      "type": "object",
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
      "type": "object",
      "properties": {
        "type": { "const": "system" },
        "subtype": { "enum": ["init", "compact_boundary"] },
        "version": { "type": "string" },
        "cwd": { "type": "string" },
        "tools": { "type": "array", "items": { "type": "string" } },
        "compact_metadata": {
          "type": "object",
          "properties": {
            "trigger": { "type": "string" },
            "pre_tokens": { "type": "integer" },
            "post_tokens": { "type": "integer" },
            "summary_tokens": { "type": "integer" }
          }
        }
      },
      "required": ["type", "subtype"]
    },
    {
      "type": "object",
      "properties": {
        "type": { "const": "stream_event" },
        "event_type": { "type": "string" },
        "index": { "type": "integer" },
        "delta": { "type": "object" }
      },
      "required": ["type", "event_type"]
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
  "oneOf": [
    {
      "properties": {
        "type": { "const": "thread.started" },
        "thread_id": { "type": "string" }
      },
      "required": ["type", "thread_id"]
    },
    {
      "properties": { "type": { "const": "turn.started" } },
      "required": ["type"]
    },
    {
      "properties": {
        "type": { "const": "turn.completed" },
        "usage": {
          "type": "object",
          "properties": {
            "input_tokens": { "type": "integer" },
            "cached_input_tokens": { "type": "integer" },
            "output_tokens": { "type": "integer" }
          },
          "required": ["input_tokens", "output_tokens"]
        }
      },
      "required": ["type", "usage"]
    },
    {
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
      "properties": {
        "type": { "const": "item.started" },
        "item_type": { "type": "string" }
      },
      "required": ["type", "item_type"]
    },
    {
      "properties": {
        "type": { "const": "item.updated" },
        "item_type": { "type": "string" }
      },
      "required": ["type", "item_type"]
    },
    {
      "properties": {
        "type": { "const": "item.completed" },
        "item_type": { "type": "string" },
        "status": { "enum": ["success", "failed"] }
      },
      "required": ["type", "item_type", "status"]
    },
    {
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
      "description": "Text content (legacy format)",
      "properties": {
        "type": { "const": "content" },
        "value": { "type": "string" }
      },
      "required": ["type", "value"]
    },
    {
      "description": "Tool call (legacy format)",
      "properties": {
        "type": { "const": "tool_call" },
        "name": { "type": "string" },
        "args": { "type": "object" }
      },
      "required": ["type", "name", "args"]
    },
    {
      "description": "Session completion",
      "properties": {
        "type": { "const": "result" },
        "status": { "enum": ["success", "error", "cancelled"] },
        "stats": {
          "type": "object",
          "properties": {
            "total_tokens": { "type": "integer" },
            "input_tokens": { "type": "integer" },
            "output_tokens": { "type": "integer" },
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
      "description": "Error event",
      "properties": {
        "type": { "const": "error" },
        "error": {
          "type": "object",
          "properties": {
            "code": { "type": "string" },
            "message": { "type": "string" }
          }
        }
      },
      "required": ["type", "error"]
    },
    {
      "description": "Retry signal on transient failure",
      "properties": {
        "type": { "const": "retry" },
        "attempt": { "type": "integer" },
        "max_attempts": { "type": "integer" },
        "delay_ms": { "type": "integer" }
      },
      "required": ["type", "attempt"]
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

| Variable | Claude | Codex | Gemini |
|----------|--------|-------|--------|
| **API Key** | `ANTHROPIC_API_KEY` | `OPENAI_API_KEY` | `GEMINI_API_KEY` / `GOOGLE_API_KEY` |
| **Model** | `CLAUDE_MODEL` | - | `GEMINI_MODEL` |
| **Debug** | `CLAUDE_DEBUG=1` | - | `-d` flag |

## Appendix C: References

- [Claude Code CLI Reference](https://code.claude.com/docs/en/cli-reference)
- [Codex CLI Documentation](https://github.com/openai/codex/tree/main/docs)
- [Gemini CLI Documentation](https://geminicli.com/docs/)
- [Claude Agent SDK](https://platform.claude.com/docs/en/agent-sdk/overview)
- [Stream-JSON Chaining](https://github.com/ruvnet/claude-flow/wiki/Stream-Chaining)

---

*End of Specification v3.0.0*
