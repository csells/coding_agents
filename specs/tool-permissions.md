# Tool Permissions Design Specification

This document specifies the tool permission and approval system used by the
coding_agents library when interacting with CLI-based coding agents (Claude
Code, Codex CLI, Gemini CLI).

---

## Table of Contents

1. [Overview](#1-overview)
2. [Execution Modes](#2-execution-modes)
3. [Agent-Specific Implementations](#3-agent-specific-implementations)
4. [Unified CodingAgent Abstraction](#4-unified-codingagent-abstraction)
5. [Decision Flow](#5-decision-flow)
6. [Best Practices](#6-best-practices)

---

## 1. Overview

Coding agents can execute potentially dangerous operations such as:

- **File writes**: Creating, modifying, or deleting files
- **Shell commands**: Running arbitrary bash commands
- **Network requests**: Making HTTP calls or accessing external services
- **System modifications**: Changing configuration, installing packages

The tool permission system provides control over when these operations are
allowed, denied, or require user approval.

### Core Principles

1. **Non-interactive modes must not block**: Prompt mode (`-p`) cannot wait for
   stdin input
2. **Safe defaults**: When in doubt, deny potentially dangerous operations
3. **Explicit opt-in for dangerous operations**: Yolo/bypass modes require
   explicit flags
4. **Consistent behavior across agents**: All agents follow the same permission
   semantics

---

## 2. Execution Modes

### 2.1 Execution Context Matrix

| Context           | Interactive | Example Use Case                    |
|-------------------|-------------|-------------------------------------|
| **REPL Mode**     | Yes         | Interactive CLI session             |
| **Prompt Mode**   | No          | One-shot command: `-p "do X"`       |
| **Programmatic**  | Maybe       | Library usage, CI/CD pipelines      |

### 2.2 Permission Modes

#### Auto-Approve (Yolo Mode)

All tool executions are automatically approved without user interaction.

```
CLI Flag: -y, --yolo
```

| Agent   | Configuration                                      |
|---------|----------------------------------------------------|
| Claude  | `ClaudePermissionMode.bypassPermissions`           |
| Codex   | `fullAuto: true` or `dangerouslyBypassAll: true`   |
| Gemini  | `GeminiApprovalMode.yolo`                          |

**Use cases:**
- Trusted automation pipelines
- Development environments where speed matters
- Scripted deployments with known safe prompts

#### Interactive Mode

Tool executions prompt the user for approval via stdin.

```
=== Approval Required ===
Tool: Write
Description: Tool execution requested: Write
File: /path/to/file.dart
Yes/No/Always/neVer? [N]:
```

**Response options:**
- `Y/yes` - Allow this operation
- `N/no` - Deny this operation (default)
- `A/always` - Allow this and future similar operations
- `V/never` - Deny this and future similar operations

**Use cases:**
- Interactive REPL sessions
- Development with human oversight
- Learning/exploration workflows

#### Auto-Deny (Non-Interactive Mode)

Tool executions are automatically denied when no interactive handler is
available.

**Trigger conditions:**
- Prompt mode (`-p`) without yolo flag
- Programmatic usage with `approvalHandler: null`
- Agent not configured for auto-approve

**Use cases:**
- Safe read-only queries
- Information retrieval tasks
- Preview mode before enabling writes

---

## 3. Agent-Specific Implementations

### 3.1 Claude Code

Claude Code uses a permission mode with optional delegate handler.

```dart
ClaudeCodingAgent(
  permissionMode: ClaudePermissionMode.defaultMode,  // or .bypassPermissions
)
```

**Permission flow:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Claude Permission Resolution                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  permissionMode == bypassPermissions?                               │
│         │                                                           │
│         ├── Yes ──▶ Auto-approve all operations                     │
│         │                                                           │
│         └── No ──▶ Check approvalHandler                            │
│                           │                                         │
│                           ├── null ──▶ Auto-deny all operations     │
│                           │                                         │
│                           └── provided ──▶ Invoke handler           │
│                                                   │                 │
│                                                   └──▶ User decides │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**CLI flags:**
- `--dangerously-skip-permissions`: Bypass all permission checks
- `--allowedTools`: Specify allowed tools explicitly

### 3.2 Codex CLI

Codex uses a combination of sandbox modes, approval policies, and approval handlers.

```dart
CodexCodingAgent(
  fullAuto: true,           // Auto-approve mode
  sandboxMode: CodexSandboxMode.workspaceWrite,  // Sandbox restrictions
)
```

**Sandbox modes:**

| Mode              | File Operations | Shell Commands |
|-------------------|-----------------|----------------|
| `readOnly`        | Read only       | Limited        |
| `workspaceWrite`  | Workspace only  | Workspace only |
| `fullAccess`      | Full system     | Full system    |

**Approval policies:**

| Policy       | Description                                           |
|--------------|-------------------------------------------------------|
| `onRequest`  | Request approval for ALL operations                   |
| `untrusted`  | Request approval for untrusted/dangerous operations   |
| `onFailure`  | Request approval only when an operation fails         |
| `never`      | Never request approval                                |

**Permission flow:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Codex Permission Resolution                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  fullAuto || dangerouslyBypassAll?                                  │
│         │                                                           │
│         ├── Yes ──▶ Use configured sandbox/policy, auto-approve     │
│         │                                                           │
│         └── No ──▶ Force readOnly sandbox + onRequest policy        │
│                           │                                         │
│                           ├── handler null ──▶ Auto-deny ALL ops    │
│                           │                                         │
│                           └── handler provided ──▶ Invoke handler   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Key insight:** The `onRequest` approval policy is essential for auto-deny to work.
Without it, Codex may execute operations without requesting approval (e.g., with
`onFailure` policy, read operations proceed without any approval check).

**CLI flags:**
- `--full-auto`: Enable autonomous mode
- `--dangerously-auto-approve`: Bypass all approvals

### 3.3 Gemini CLI

Gemini uses approval modes that control available tools.

```dart
GeminiCodingAgent(
  approvalMode: GeminiApprovalMode.yolo,  // or .defaultMode, .autoEdit
)
```

**Approval modes:**

| Mode          | Write Tools | Shell Commands | Notes                    |
|---------------|-------------|----------------|--------------------------|
| `defaultMode` | No          | Limited        | Safe, read-only          |
| `autoEdit`    | Yes         | Limited        | Auto-approve file edits  |
| `yolo`        | Yes         | Yes            | Full autonomous mode     |

**Permission flow:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Gemini Permission Resolution                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  approvalMode == yolo?                                              │
│         │                                                           │
│         ├── Yes ──▶ All tools available, auto-approve               │
│         │                                                           │
│         └── No ──▶ approvalMode == autoEdit?                        │
│                           │                                         │
│                           ├── Yes ──▶ Write tools available         │
│                           │                                         │
│                           └── No ──▶ Limited tools (effectivedeny)  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Note:** Gemini CLI does not support interactive approval handlers. Permission
control is entirely mode-based.

---

## 4. Unified CodingAgent Abstraction

The unified `CodingAgent` interface provides consistent permission handling
across all agents.

### 4.1 Session Creation

```dart
final session = await agent.createSession(
  projectDirectory: '/path/to/project',
  approvalHandler: handler,  // null for auto-deny, function for interactive
);
```

### 4.2 ToolApprovalHandler

```dart
typedef ToolApprovalHandler = Future<ToolApprovalResponse> Function(
  ToolApprovalRequest request,
);

class ToolApprovalRequest {
  final String id;
  final String toolName;
  final String description;
  final Map<String, dynamic>? input;
  final String? command;
  final String? filePath;
}

class ToolApprovalResponse {
  final ToolApprovalDecision decision;
  final String? message;
}

enum ToolApprovalDecision {
  allow,       // Allow this operation
  deny,        // Deny this operation
  allowAlways, // Allow this and future similar operations
  denyAlways,  // Deny this and future similar operations
}
```

### 4.3 Unified Permission Resolution

All agents follow this resolution order:

1. **Check agent configuration**: If configured for bypass/yolo, auto-approve
2. **Check approval handler**: If `null`, auto-deny
3. **Invoke handler**: Let user decide interactively

---

## 5. Decision Flow

### 5.1 CLI Usage Decision Tree

```
User runs CLI command
         │
         ├── Has -y/--yolo flag?
         │         │
         │         ├── Yes ──▶ Configure agent with bypass mode
         │         │                    │
         │         │                    └──▶ All operations auto-approved
         │         │
         │         └── No ──▶ Check execution context
         │                           │
         │                           ├── Prompt mode (-p)?
         │                           │         │
         │                           │         └──▶ Pass null handler
         │                           │                    │
         │                           │                    └──▶ Auto-deny
         │                           │
         │                           └── REPL mode?
         │                                     │
         │                                     └──▶ Pass interactive handler
         │                                                    │
         │                                                    └──▶ Prompt user
```

### 5.2 Programmatic Usage

```dart
// Auto-approve mode
final agent = ClaudeCodingAgent(
  permissionMode: ClaudePermissionMode.bypassPermissions,
);

// Auto-deny mode (safe queries)
final session = await agent.createSession(
  projectDirectory: dir,
  approvalHandler: null,  // Auto-deny
);

// Interactive mode
final session = await agent.createSession(
  projectDirectory: dir,
  approvalHandler: (request) async {
    // Custom logic to approve/deny
    return ToolApprovalResponse(decision: ToolApprovalDecision.allow);
  },
);
```

---

## 6. Best Practices

### 6.1 Choosing the Right Mode

| Scenario                              | Recommended Mode        |
|---------------------------------------|-------------------------|
| CI/CD automation                      | Auto-approve (yolo)     |
| Development REPL                      | Interactive             |
| Information queries                   | Auto-deny (safe)        |
| Trusted scripts                       | Auto-approve            |
| Untrusted/unknown prompts             | Auto-deny or Interactive|

### 6.2 Security Considerations

1. **Never use yolo mode with untrusted prompts**: Arbitrary code execution risk
2. **Prefer auto-deny for automated systems**: Fail-safe defaults
3. **Review "always" decisions**: They persist for the session
4. **Audit tool usage**: Log which tools are invoked and their outcomes

### 6.3 Error Handling

- **Auto-deny is not an error**: It's expected behavior for non-interactive mode
- **Don't swallow permission denials**: Let them propagate to inform the user
- **Log approval decisions**: Useful for debugging and auditing

### 6.4 Testing

```dart
// Test auto-deny behavior
test('prompt mode auto-denies writes', () async {
  final agent = ClaudeCodingAgent();
  final session = await agent.createSession(
    projectDirectory: testDir,
    approvalHandler: null,  // Auto-deny
  );

  await session.sendMessage('Create a file');
  // Verify file was not created (write was denied)
  expect(File('$testDir/file.txt').existsSync(), isFalse);
});
```

---

## Appendix: Quick Reference

### Permission Mode Summary

| Mode           | Handler   | Result      | Use Case                    |
|----------------|-----------|-------------|-----------------------------|
| Bypass/Yolo    | N/A       | Auto-approve| Automation, trusted scripts |
| Interactive    | Provided  | Prompt user | REPL, development           |
| Non-interactive| null      | Auto-deny   | Safe queries, prompt mode   |

### CLI Flag Reference

| Agent   | Auto-Approve Flag        | Notes                          |
|---------|--------------------------|--------------------------------|
| Claude  | `-y`, `--yolo`           | Also: `--dangerously-skip-permissions` |
| Codex   | `-y`, `--yolo`           | Maps to `--full-auto`          |
| Gemini  | `-y`, `--yolo`           | Maps to approval mode          |
