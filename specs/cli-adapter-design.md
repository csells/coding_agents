# CLI Agent Adapter Design Specification

**Version:** 1.0.0
**Date:** December 3, 2025
**Purpose:** Design specification for Dart adapters that wrap Claude Code, Codex CLI, and Gemini CLI, exposing CLI-specific APIs for multi-turn sessions, streaming events, tool permission handling, and session management.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Claude Code Adapter](#3-claude-code-adapter)
4. [Codex CLI Adapter](#4-codex-cli-adapter)
5. [Gemini CLI Adapter](#5-gemini-cli-adapter)
6. [Implementation Notes](#6-implementation-notes)

---

## 1. Overview

### 1.1 Goals

- Provide Dart wrappers for three CLI coding agents: Claude Code, Codex CLI, and Gemini CLI
- Enable multi-turn sessions with streaming event output
- Support session creation, resumption, and listing
- Handle tool permission policies with CLI-specific mechanisms
- Expose CLI-specific types with no normalization or shared abstractions

### 1.2 Design Principles

1. **CLI-specific types**: Each adapter has its own event types, config types, and session types
2. **No shared code**: Adapters are independent; no common base classes or interfaces
3. **Idiomatic Dart**: Use `Stream<T>` for events, `Future<T>` for async operations
4. **Process management hidden**: Adapters internally manage process lifecycle
5. **CWD-scoped**: Each client is initialized with a working directory; all operations are scoped to that directory
6. **Errors as exceptions**: No try-catch wrappers; exceptions propagate to consumer

### 1.3 Package Dependencies

- `mcp_dart`: MCP server implementation for Claude permission delegation
- `json_annotation` / `json_serializable`: JSON serialization
- Core Dart: `dart:async`, `dart:convert`, `dart:io`

---

## 2. Architecture

### 2.1 Directory Structure

```
lib/
└── src/
    └── adapters/
        ├── claude/
        │   ├── claude_client.dart
        │   ├── claude_session.dart
        │   ├── claude_config.dart
        │   ├── claude_events.dart
        │   ├── claude_types.dart
        │   └── claude_permission_server.dart
        ├── codex/
        │   ├── codex_client.dart
        │   ├── codex_session.dart
        │   ├── codex_config.dart
        │   ├── codex_events.dart
        │   └── codex_types.dart
        └── gemini/
            ├── gemini_client.dart
            ├── gemini_session.dart
            ├── gemini_config.dart
            ├── gemini_events.dart
            └── gemini_types.dart
```

### 2.2 Common Patterns (Not Shared Code)

Each adapter follows similar patterns but with CLI-specific implementations:

```
Client (per CWD)
  ├── createSession(config) → Session
  ├── resumeSession(sessionId) → Session
  └── listSessions() → List<SessionInfo>

Session
  ├── sessionId: String
  ├── events: Stream<Event>
  ├── send(message) → void
  └── cancel() → void
```

---

## 3. Claude Code Adapter

### 3.1 Overview

Claude Code uses a **long-lived bidirectional JSONL process**. A single process handles multiple turns via stdin/stdout. The adapter spawns an internal MCP server for permission delegation.

### 3.2 Types

#### claude_types.dart

```dart
/// Claude permission modes
enum ClaudePermissionMode {
  /// Prompt for dangerous tools (default behavior)
  defaultMode,

  /// Auto-approve file edits
  acceptEdits,

  /// Skip all permission prompts
  bypassPermissions,

  /// Delegate to permission handler callback
  delegate,
}

/// Information about a stored Claude session
@JsonSerializable()
class ClaudeSessionInfo {
  final String sessionId;
  final String cwd;
  final String? gitBranch;
  final DateTime timestamp;
  final DateTime lastUpdated;

  ClaudeSessionInfo({
    required this.sessionId,
    required this.cwd,
    this.gitBranch,
    required this.timestamp,
    required this.lastUpdated,
  });

  factory ClaudeSessionInfo.fromJson(Map<String, dynamic> json) =>
      _$ClaudeSessionInfoFromJson(json);
  Map<String, dynamic> toJson() => _$ClaudeSessionInfoToJson(this);
}

/// Tool permission request from Claude
@JsonSerializable()
class ClaudeToolPermissionRequest {
  final String toolName;
  final Map<String, dynamic> toolInput;
  final String sessionId;
  final int turnId;

  ClaudeToolPermissionRequest({
    required this.toolName,
    required this.toolInput,
    required this.sessionId,
    required this.turnId,
  });

  factory ClaudeToolPermissionRequest.fromJson(Map<String, dynamic> json) =>
      _$ClaudeToolPermissionRequestFromJson(json);
  Map<String, dynamic> toJson() => _$ClaudeToolPermissionRequestToJson(this);
}

/// Response to a tool permission request
@JsonSerializable()
class ClaudeToolPermissionResponse {
  final ClaudePermissionBehavior behavior;
  final Map<String, dynamic>? updatedInput;
  final String? message;

  ClaudeToolPermissionResponse({
    required this.behavior,
    this.updatedInput,
    this.message,
  });

  factory ClaudeToolPermissionResponse.fromJson(Map<String, dynamic> json) =>
      _$ClaudeToolPermissionResponseFromJson(json);
  Map<String, dynamic> toJson() => _$ClaudeToolPermissionResponseToJson(this);
}

enum ClaudePermissionBehavior {
  allow,
  deny,
  allowAlways,
  denyAlways,
}

/// Token usage statistics
@JsonSerializable()
class ClaudeUsage {
  final int inputTokens;
  final int outputTokens;
  final int? cacheCreationInputTokens;
  final int? cacheReadInputTokens;

  ClaudeUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.cacheCreationInputTokens,
    this.cacheReadInputTokens,
  });

  factory ClaudeUsage.fromJson(Map<String, dynamic> json) =>
      _$ClaudeUsageFromJson(json);
  Map<String, dynamic> toJson() => _$ClaudeUsageToJson(this);
}

/// Content block in a message
sealed class ClaudeContentBlock {
  const ClaudeContentBlock();

  factory ClaudeContentBlock.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'text' => ClaudeTextBlock.fromJson(json),
      'thinking' => ClaudeThinkingBlock.fromJson(json),
      'tool_use' => ClaudeToolUseBlock.fromJson(json),
      'tool_result' => ClaudeToolResultBlock.fromJson(json),
      _ => ClaudeUnknownBlock(type: type, data: json),
    };
  }
}

@JsonSerializable()
class ClaudeTextBlock extends ClaudeContentBlock {
  final String text;

  const ClaudeTextBlock({required this.text});

  factory ClaudeTextBlock.fromJson(Map<String, dynamic> json) =>
      _$ClaudeTextBlockFromJson(json);
}

@JsonSerializable()
class ClaudeThinkingBlock extends ClaudeContentBlock {
  final String thinking;

  const ClaudeThinkingBlock({required this.thinking});

  factory ClaudeThinkingBlock.fromJson(Map<String, dynamic> json) =>
      _$ClaudeThinkingBlockFromJson(json);
}

@JsonSerializable()
class ClaudeToolUseBlock extends ClaudeContentBlock {
  final String id;
  final String name;
  final Map<String, dynamic> input;

  const ClaudeToolUseBlock({
    required this.id,
    required this.name,
    required this.input,
  });

  factory ClaudeToolUseBlock.fromJson(Map<String, dynamic> json) =>
      _$ClaudeToolUseBlockFromJson(json);
}

@JsonSerializable()
class ClaudeToolResultBlock extends ClaudeContentBlock {
  final String toolUseId;
  final String content;
  final bool? isError;

  const ClaudeToolResultBlock({
    required this.toolUseId,
    required this.content,
    this.isError,
  });

  factory ClaudeToolResultBlock.fromJson(Map<String, dynamic> json) =>
      _$ClaudeToolResultBlockFromJson(json);
}

class ClaudeUnknownBlock extends ClaudeContentBlock {
  final String type;
  final Map<String, dynamic> data;

  const ClaudeUnknownBlock({required this.type, required this.data});
}
```

#### claude_events.dart

```dart
/// Base class for all Claude streaming events
sealed class ClaudeEvent {
  final String sessionId;
  final int turnId;
  final DateTime timestamp;

  const ClaudeEvent({
    required this.sessionId,
    required this.turnId,
    required this.timestamp,
  });

  factory ClaudeEvent.fromJson(Map<String, dynamic> json, int turnId) {
    final type = json['type'] as String;
    final sessionId = json['session_id'] as String? ?? '';
    final timestamp = DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now();

    return switch (type) {
      'init' => ClaudeInitEvent.fromJson(json, turnId),
      'assistant' => ClaudeAssistantEvent.fromJson(json, turnId),
      'user' => ClaudeUserEvent.fromJson(json, turnId),
      'result' => ClaudeResultEvent.fromJson(json, turnId),
      'system' => ClaudeSystemEvent.fromJson(json, turnId),
      _ => ClaudeUnknownEvent(
          sessionId: sessionId,
          turnId: turnId,
          timestamp: timestamp,
          type: type,
          data: json,
        ),
    };
  }
}

/// Session initialization event
@JsonSerializable()
class ClaudeInitEvent extends ClaudeEvent {
  final String model;

  ClaudeInitEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.model,
  });

  factory ClaudeInitEvent.fromJson(Map<String, dynamic> json, int turnId) =>
      ClaudeInitEvent(
        sessionId: json['session_id'] as String,
        turnId: turnId,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        model: json['model'] as String? ?? '',
      );
}

/// Assistant message event
@JsonSerializable()
class ClaudeAssistantEvent extends ClaudeEvent {
  final List<ClaudeContentBlock> content;
  final ClaudeUsage? usage;

  ClaudeAssistantEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.content,
    this.usage,
  });

  factory ClaudeAssistantEvent.fromJson(Map<String, dynamic> json, int turnId) {
    final message = json['message'] as Map<String, dynamic>?;
    final contentList = (message?['content'] as List<dynamic>?)
        ?.map((e) => ClaudeContentBlock.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];
    final usage = message?['usage'] != null
        ? ClaudeUsage.fromJson(message!['usage'] as Map<String, dynamic>)
        : null;

    return ClaudeAssistantEvent(
      sessionId: json['session_id'] as String? ?? '',
      turnId: turnId,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      content: contentList,
      usage: usage,
    );
  }
}

/// User message event (typically tool results)
@JsonSerializable()
class ClaudeUserEvent extends ClaudeEvent {
  final List<ClaudeContentBlock> content;

  ClaudeUserEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.content,
  });

  factory ClaudeUserEvent.fromJson(Map<String, dynamic> json, int turnId) {
    final message = json['message'] as Map<String, dynamic>?;
    final contentList = (message?['content'] as List<dynamic>?)
        ?.map((e) => ClaudeContentBlock.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];

    return ClaudeUserEvent(
      sessionId: json['session_id'] as String? ?? '',
      turnId: turnId,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      content: contentList,
    );
  }
}

/// Turn/session result event
@JsonSerializable()
class ClaudeResultEvent extends ClaudeEvent {
  final String subtype; // "success", "error", "cancelled"
  final double? costUsd;
  final int? durationMs;
  final ClaudeUsage? usage;
  final String? error;

  ClaudeResultEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.subtype,
    this.costUsd,
    this.durationMs,
    this.usage,
    this.error,
  });

  factory ClaudeResultEvent.fromJson(Map<String, dynamic> json, int turnId) =>
      ClaudeResultEvent(
        sessionId: json['session_id'] as String? ?? '',
        turnId: turnId,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        subtype: json['subtype'] as String? ?? 'unknown',
        costUsd: (json['cost_usd'] as num?)?.toDouble(),
        durationMs: json['duration_ms'] as int?,
        usage: json['usage'] != null
            ? ClaudeUsage.fromJson(json['usage'] as Map<String, dynamic>)
            : null,
        error: json['error'] as String?,
      );
}

/// System event (init info, compaction, etc.)
@JsonSerializable()
class ClaudeSystemEvent extends ClaudeEvent {
  final String subtype;
  final Map<String, dynamic> data;

  ClaudeSystemEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.subtype,
    required this.data,
  });

  factory ClaudeSystemEvent.fromJson(Map<String, dynamic> json, int turnId) =>
      ClaudeSystemEvent(
        sessionId: json['session_id'] as String? ?? '',
        turnId: turnId,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        subtype: json['subtype'] as String? ?? 'unknown',
        data: json,
      );
}

/// Unknown event type (forward compatibility)
class ClaudeUnknownEvent extends ClaudeEvent {
  final String type;
  final Map<String, dynamic> data;

  ClaudeUnknownEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.type,
    required this.data,
  });
}
```

#### claude_config.dart

```dart
/// Permission handler callback type
typedef ClaudePermissionHandler = Future<ClaudeToolPermissionResponse> Function(
  ClaudeToolPermissionRequest request,
);

/// Configuration for a Claude session
class ClaudeSessionConfig {
  /// Permission handling mode
  final ClaudePermissionMode permissionMode;

  /// Permission handler callback (required when permissionMode is delegate)
  final ClaudePermissionHandler? permissionHandler;

  /// Model to use (e.g., "claude-sonnet-4-5-20250929")
  final String? model;

  /// System prompt override
  final String? systemPrompt;

  /// System prompt to append
  final String? appendSystemPrompt;

  /// Maximum agentic turns
  final int? maxTurns;

  /// Allowed tools list
  final List<String>? allowedTools;

  /// Disallowed tools list
  final List<String>? disallowedTools;

  ClaudeSessionConfig({
    this.permissionMode = ClaudePermissionMode.defaultMode,
    this.permissionHandler,
    this.model,
    this.systemPrompt,
    this.appendSystemPrompt,
    this.maxTurns,
    this.allowedTools,
    this.disallowedTools,
  }) {
    if (permissionMode == ClaudePermissionMode.delegate && permissionHandler == null) {
      throw ArgumentError('permissionHandler is required when permissionMode is delegate');
    }
  }
}
```

#### claude_session.dart

```dart
/// A Claude Code session
class ClaudeSession {
  /// Unique session identifier
  final String sessionId;

  /// Stream of session events
  Stream<ClaudeEvent> get events => _eventController.stream;

  final StreamController<ClaudeEvent> _eventController;
  final Process _process;
  final int Function() _nextTurnId;
  int _currentTurnId = 0;

  ClaudeSession._({
    required this.sessionId,
    required StreamController<ClaudeEvent> eventController,
    required Process process,
    required int Function() nextTurnId,
  })  : _eventController = eventController,
        _process = process,
        _nextTurnId = nextTurnId;

  /// Send a follow-up message to the session
  ///
  /// The message is written to stdin of the running Claude process.
  /// Events will be emitted to [events] stream as responses arrive.
  void send(String message) {
    _currentTurnId = _nextTurnId();

    final input = jsonEncode({
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': message}
        ]
      }
    });

    _process.stdin.writeln(input);
  }

  /// Cancel the current operation
  Future<void> cancel() async {
    _process.kill(ProcessSignal.sigterm);
    await _eventController.close();
  }
}
```

#### claude_client.dart

```dart
/// Client for Claude Code CLI operations
class ClaudeClient {
  /// Working directory for this client
  final String cwd;

  int _turnCounter = 0;

  ClaudeClient({required this.cwd});

  /// Create a new Claude session
  ///
  /// Spawns a long-lived Claude process with bidirectional JSONL streaming.
  Future<ClaudeSession> createSession(
    String initialPrompt,
    ClaudeSessionConfig config,
  ) async {
    final args = _buildArgs(config, initialPrompt, null);

    final process = await Process.start('claude', args, workingDirectory: cwd);
    final eventController = StreamController<ClaudeEvent>.broadcast();

    String? sessionId;

    // Start MCP permission server if needed
    if (config.permissionMode == ClaudePermissionMode.delegate) {
      await _startPermissionServer(config.permissionHandler!);
    }

    // Parse stdout JSONL
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty || !line.trim().startsWith('{')) return;

      final json = jsonDecode(line) as Map<String, dynamic>;
      final event = ClaudeEvent.fromJson(json, _turnCounter);

      if (event is ClaudeInitEvent) {
        sessionId = event.sessionId;
      }

      eventController.add(event);
    });

    // Handle process exit
    process.exitCode.then((code) {
      if (code != 0) {
        eventController.addError(
          ClaudeProcessException('Claude process exited with code $code'),
        );
      }
      eventController.close();
    });

    // Wait for init event to get session ID
    await eventController.stream.firstWhere((e) => e is ClaudeInitEvent);

    _turnCounter++;

    return ClaudeSession._(
      sessionId: sessionId!,
      eventController: eventController,
      process: process,
      nextTurnId: () => ++_turnCounter,
    );
  }

  /// Resume an existing session
  Future<ClaudeSession> resumeSession(
    String sessionId,
    String prompt,
    ClaudeSessionConfig config,
  ) async {
    final args = _buildArgs(config, prompt, sessionId);

    final process = await Process.start('claude', args, workingDirectory: cwd);
    final eventController = StreamController<ClaudeEvent>.broadcast();

    // Start MCP permission server if needed
    if (config.permissionMode == ClaudePermissionMode.delegate) {
      await _startPermissionServer(config.permissionHandler!);
    }

    // Parse stdout JSONL
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty || !line.trim().startsWith('{')) return;

      final json = jsonDecode(line) as Map<String, dynamic>;
      final event = ClaudeEvent.fromJson(json, _turnCounter);
      eventController.add(event);
    });

    process.exitCode.then((code) {
      if (code != 0) {
        eventController.addError(
          ClaudeProcessException('Claude process exited with code $code'),
        );
      }
      eventController.close();
    });

    _turnCounter++;

    return ClaudeSession._(
      sessionId: sessionId,
      eventController: eventController,
      process: process,
      nextTurnId: () => ++_turnCounter,
    );
  }

  /// List all sessions for this working directory
  Future<List<ClaudeSessionInfo>> listSessions() async {
    final encodedCwd = cwd.replaceAll('/', '-');
    final projectDir = Directory('${Platform.environment['HOME']}/.claude/projects/$encodedCwd');

    if (!await projectDir.exists()) {
      return [];
    }

    final sessions = <ClaudeSessionInfo>[];

    await for (final file in projectDir.list()) {
      if (file is! File || !file.path.endsWith('.jsonl')) continue;

      // Skip agent sub-sessions
      final filename = file.path.split('/').last;
      if (filename.startsWith('agent-')) continue;

      final info = await _parseSessionFile(file);
      if (info != null) {
        sessions.add(info);
      }
    }

    // Sort by lastUpdated descending
    sessions.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));

    return sessions;
  }

  List<String> _buildArgs(ClaudeSessionConfig config, String prompt, String? resumeSessionId) {
    return [
      '-p', prompt,
      '--output-format', 'stream-json',
      '--input-format', 'stream-json',
      if (resumeSessionId != null) ...['--resume', resumeSessionId],
      if (config.permissionMode == ClaudePermissionMode.acceptEdits)
        ...['--permission-mode', 'acceptEdits'],
      if (config.permissionMode == ClaudePermissionMode.bypassPermissions)
        ...['--permission-mode', 'bypassPermissions'],
      if (config.permissionMode == ClaudePermissionMode.delegate)
        ...['--permission-prompt-tool', 'mcp__claude_adapter__handle_permission'],
      if (config.model != null) ...['--model', config.model!],
      if (config.systemPrompt != null) ...['--system-prompt', config.systemPrompt!],
      if (config.appendSystemPrompt != null) ...['--append-system-prompt', config.appendSystemPrompt!],
      if (config.maxTurns != null) ...['--max-turns', config.maxTurns.toString()],
      if (config.allowedTools != null) ...['--allowedTools', ...config.allowedTools!],
      if (config.disallowedTools != null) ...['--disallowedTools', ...config.disallowedTools!],
    ];
  }

  Future<ClaudeSessionInfo?> _parseSessionFile(File file) async {
    // Implementation reads first few lines to extract metadata
    // Returns null if file is empty or unparseable
  }

  Future<void> _startPermissionServer(ClaudePermissionHandler handler) async {
    // Implementation uses mcp_dart to create an MCP server
    // that handles permission requests and calls the handler
  }
}

class ClaudeProcessException implements Exception {
  final String message;
  ClaudeProcessException(this.message);

  @override
  String toString() => 'ClaudeProcessException: $message';
}
```

---

## 4. Codex CLI Adapter

### 4.1 Overview

Codex CLI uses a **process-per-turn model**. Each user message spawns a new process. Session state is persisted to disk and restored via the `resume` subcommand.

### 4.2 Types

#### codex_types.dart

```dart
/// Codex approval policies
enum CodexApprovalPolicy {
  /// Model decides when to ask
  onRequest,

  /// Only trusted commands auto-approved
  untrusted,

  /// Ask only if command fails
  onFailure,

  /// Never ask (return failures to model)
  never,
}

/// Codex sandbox modes
enum CodexSandboxMode {
  /// Read-only access
  readOnly,

  /// Write to workspace and tmp only
  workspaceWrite,

  /// Full unrestricted access
  dangerFullAccess,
}

/// Information about a stored Codex session
@JsonSerializable()
class CodexSessionInfo {
  final String threadId;
  final DateTime timestamp;
  final String? gitBranch;
  final String? repositoryUrl;
  final String? cwd;
  final DateTime lastUpdated;

  CodexSessionInfo({
    required this.threadId,
    required this.timestamp,
    this.gitBranch,
    this.repositoryUrl,
    this.cwd,
    required this.lastUpdated,
  });

  factory CodexSessionInfo.fromJson(Map<String, dynamic> json) =>
      _$CodexSessionInfoFromJson(json);
  Map<String, dynamic> toJson() => _$CodexSessionInfoToJson(this);
}

/// Token usage for a turn
@JsonSerializable()
class CodexUsage {
  final int inputTokens;
  final int outputTokens;
  final int? cachedInputTokens;

  CodexUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.cachedInputTokens,
  });

  factory CodexUsage.fromJson(Map<String, dynamic> json) =>
      _$CodexUsageFromJson(json);
  Map<String, dynamic> toJson() => _$CodexUsageToJson(this);
}

/// Item types in Codex events
enum CodexItemType {
  agentMessage,
  reasoning,
  toolCall,
  fileChange,
  mcpToolCall,
  webSearch,
  todoList,
  error,
}

/// A Codex item (message, tool call, etc.)
sealed class CodexItem {
  final String id;
  final CodexItemType type;

  const CodexItem({required this.id, required this.type});

  factory CodexItem.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'agent_message' => CodexAgentMessageItem.fromJson(json),
      'reasoning' => CodexReasoningItem.fromJson(json),
      'tool_call' || 'shell' => CodexToolCallItem.fromJson(json),
      'file_change' => CodexFileChangeItem.fromJson(json),
      'mcp_tool_call' => CodexMcpToolCallItem.fromJson(json),
      'web_search' => CodexWebSearchItem.fromJson(json),
      'todo_list' => CodexTodoListItem.fromJson(json),
      _ => CodexUnknownItem(id: json['id'] as String? ?? '', type: CodexItemType.error, data: json),
    };
  }
}

@JsonSerializable()
class CodexAgentMessageItem extends CodexItem {
  final String text;

  CodexAgentMessageItem({
    required super.id,
    required this.text,
  }) : super(type: CodexItemType.agentMessage);

  factory CodexAgentMessageItem.fromJson(Map<String, dynamic> json) =>
      CodexAgentMessageItem(
        id: json['id'] as String? ?? '',
        text: json['text'] as String? ?? '',
      );
}

@JsonSerializable()
class CodexReasoningItem extends CodexItem {
  final String reasoning;
  final String? summary;

  CodexReasoningItem({
    required super.id,
    required this.reasoning,
    this.summary,
  }) : super(type: CodexItemType.reasoning);

  factory CodexReasoningItem.fromJson(Map<String, dynamic> json) =>
      CodexReasoningItem(
        id: json['id'] as String? ?? '',
        reasoning: json['reasoning'] as String? ?? '',
        summary: json['summary'] as String?,
      );
}

@JsonSerializable()
class CodexToolCallItem extends CodexItem {
  final String name;
  final Map<String, dynamic> arguments;
  final String? output;
  final int? exitCode;

  CodexToolCallItem({
    required super.id,
    required this.name,
    required this.arguments,
    this.output,
    this.exitCode,
  }) : super(type: CodexItemType.toolCall);

  factory CodexToolCallItem.fromJson(Map<String, dynamic> json) =>
      CodexToolCallItem(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        arguments: json['arguments'] as Map<String, dynamic>? ?? {},
        output: json['output'] as String?,
        exitCode: json['exit_code'] as int?,
      );
}

@JsonSerializable()
class CodexFileChangeItem extends CodexItem {
  final String path;
  final String? before;
  final String? after;
  final String? diff;

  CodexFileChangeItem({
    required super.id,
    required this.path,
    this.before,
    this.after,
    this.diff,
  }) : super(type: CodexItemType.fileChange);

  factory CodexFileChangeItem.fromJson(Map<String, dynamic> json) =>
      CodexFileChangeItem(
        id: json['id'] as String? ?? '',
        path: json['path'] as String? ?? '',
        before: json['before'] as String?,
        after: json['after'] as String?,
        diff: json['diff'] as String?,
      );
}

@JsonSerializable()
class CodexMcpToolCallItem extends CodexItem {
  final String toolName;
  final Map<String, dynamic> toolInput;
  final dynamic toolResult;

  CodexMcpToolCallItem({
    required super.id,
    required this.toolName,
    required this.toolInput,
    this.toolResult,
  }) : super(type: CodexItemType.mcpToolCall);

  factory CodexMcpToolCallItem.fromJson(Map<String, dynamic> json) =>
      CodexMcpToolCallItem(
        id: json['id'] as String? ?? '',
        toolName: json['tool_name'] as String? ?? '',
        toolInput: json['tool_input'] as Map<String, dynamic>? ?? {},
        toolResult: json['tool_result'],
      );
}

@JsonSerializable()
class CodexWebSearchItem extends CodexItem {
  final String query;
  final List<Map<String, dynamic>> results;

  CodexWebSearchItem({
    required super.id,
    required this.query,
    required this.results,
  }) : super(type: CodexItemType.webSearch);

  factory CodexWebSearchItem.fromJson(Map<String, dynamic> json) =>
      CodexWebSearchItem(
        id: json['id'] as String? ?? '',
        query: json['query'] as String? ?? '',
        results: (json['results'] as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ?? [],
      );
}

@JsonSerializable()
class CodexTodoListItem extends CodexItem {
  final List<Map<String, dynamic>> items;

  CodexTodoListItem({
    required super.id,
    required this.items,
  }) : super(type: CodexItemType.todoList);

  factory CodexTodoListItem.fromJson(Map<String, dynamic> json) =>
      CodexTodoListItem(
        id: json['id'] as String? ?? '',
        items: (json['items'] as List<dynamic>?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ?? [],
      );
}

class CodexUnknownItem extends CodexItem {
  final Map<String, dynamic> data;

  CodexUnknownItem({
    required super.id,
    required super.type,
    required this.data,
  });
}
```

#### codex_events.dart

```dart
/// Base class for all Codex streaming events
sealed class CodexEvent {
  final String threadId;
  final int turnId;
  final DateTime timestamp;

  const CodexEvent({
    required this.threadId,
    required this.turnId,
    required this.timestamp,
  });

  factory CodexEvent.fromJson(Map<String, dynamic> json, String threadId, int turnId) {
    final type = json['type'] as String;
    final timestamp = DateTime.now(); // Codex doesn't include timestamp in all events

    return switch (type) {
      'thread.started' => CodexThreadStartedEvent.fromJson(json, turnId),
      'turn.started' => CodexTurnStartedEvent(threadId: threadId, turnId: turnId, timestamp: timestamp),
      'turn.completed' => CodexTurnCompletedEvent.fromJson(json, threadId, turnId),
      'turn.failed' => CodexTurnFailedEvent.fromJson(json, threadId, turnId),
      'item.started' => CodexItemStartedEvent.fromJson(json, threadId, turnId),
      'item.updated' => CodexItemUpdatedEvent.fromJson(json, threadId, turnId),
      'item.completed' => CodexItemCompletedEvent.fromJson(json, threadId, turnId),
      'error' => CodexErrorEvent.fromJson(json, threadId, turnId),
      _ => CodexUnknownEvent(threadId: threadId, turnId: turnId, timestamp: timestamp, type: type, data: json),
    };
  }
}

/// Thread (session) started event
@JsonSerializable()
class CodexThreadStartedEvent extends CodexEvent {
  CodexThreadStartedEvent({
    required super.threadId,
    required super.turnId,
    required super.timestamp,
  });

  factory CodexThreadStartedEvent.fromJson(Map<String, dynamic> json, int turnId) =>
      CodexThreadStartedEvent(
        threadId: json['thread_id'] as String,
        turnId: turnId,
        timestamp: DateTime.now(),
      );
}

/// Turn started event
class CodexTurnStartedEvent extends CodexEvent {
  CodexTurnStartedEvent({
    required super.threadId,
    required super.turnId,
    required super.timestamp,
  });
}

/// Turn completed event
@JsonSerializable()
class CodexTurnCompletedEvent extends CodexEvent {
  final CodexUsage? usage;

  CodexTurnCompletedEvent({
    required super.threadId,
    required super.turnId,
    required super.timestamp,
    this.usage,
  });

  factory CodexTurnCompletedEvent.fromJson(Map<String, dynamic> json, String threadId, int turnId) =>
      CodexTurnCompletedEvent(
        threadId: threadId,
        turnId: turnId,
        timestamp: DateTime.now(),
        usage: json['usage'] != null
            ? CodexUsage.fromJson(json['usage'] as Map<String, dynamic>)
            : null,
      );
}

/// Turn failed event
@JsonSerializable()
class CodexTurnFailedEvent extends CodexEvent {
  final String message;

  CodexTurnFailedEvent({
    required super.threadId,
    required super.turnId,
    required super.timestamp,
    required this.message,
  });

  factory CodexTurnFailedEvent.fromJson(Map<String, dynamic> json, String threadId, int turnId) =>
      CodexTurnFailedEvent(
        threadId: threadId,
        turnId: turnId,
        timestamp: DateTime.now(),
        message: (json['error'] as Map<String, dynamic>?)?['message'] as String? ?? 'Unknown error',
      );
}

/// Item started event
@JsonSerializable()
class CodexItemStartedEvent extends CodexEvent {
  final CodexItem item;

  CodexItemStartedEvent({
    required super.threadId,
    required super.turnId,
    required super.timestamp,
    required this.item,
  });

  factory CodexItemStartedEvent.fromJson(Map<String, dynamic> json, String threadId, int turnId) =>
      CodexItemStartedEvent(
        threadId: threadId,
        turnId: turnId,
        timestamp: DateTime.now(),
        item: CodexItem.fromJson(json['item'] as Map<String, dynamic>),
      );
}

/// Item updated event (streaming content)
@JsonSerializable()
class CodexItemUpdatedEvent extends CodexEvent {
  final CodexItem item;

  CodexItemUpdatedEvent({
    required super.threadId,
    required super.turnId,
    required super.timestamp,
    required this.item,
  });

  factory CodexItemUpdatedEvent.fromJson(Map<String, dynamic> json, String threadId, int turnId) =>
      CodexItemUpdatedEvent(
        threadId: threadId,
        turnId: turnId,
        timestamp: DateTime.now(),
        item: CodexItem.fromJson(json['item'] as Map<String, dynamic>),
      );
}

/// Item completed event
@JsonSerializable()
class CodexItemCompletedEvent extends CodexEvent {
  final CodexItem item;
  final String status; // "success", "failed"

  CodexItemCompletedEvent({
    required super.threadId,
    required super.turnId,
    required super.timestamp,
    required this.item,
    required this.status,
  });

  factory CodexItemCompletedEvent.fromJson(Map<String, dynamic> json, String threadId, int turnId) =>
      CodexItemCompletedEvent(
        threadId: threadId,
        turnId: turnId,
        timestamp: DateTime.now(),
        item: CodexItem.fromJson(json['item'] as Map<String, dynamic>),
        status: json['status'] as String? ?? 'unknown',
      );
}

/// Error event
@JsonSerializable()
class CodexErrorEvent extends CodexEvent {
  final String message;

  CodexErrorEvent({
    required super.threadId,
    required super.turnId,
    required super.timestamp,
    required this.message,
  });

  factory CodexErrorEvent.fromJson(Map<String, dynamic> json, String threadId, int turnId) =>
      CodexErrorEvent(
        threadId: threadId,
        turnId: turnId,
        timestamp: DateTime.now(),
        message: json['message'] as String? ?? 'Unknown error',
      );
}

/// Unknown event type
class CodexUnknownEvent extends CodexEvent {
  final String type;
  final Map<String, dynamic> data;

  CodexUnknownEvent({
    required super.threadId,
    required super.turnId,
    required super.timestamp,
    required this.type,
    required this.data,
  });
}
```

#### codex_config.dart

```dart
/// Configuration for a Codex session
class CodexSessionConfig {
  /// Approval policy for tool execution
  final CodexApprovalPolicy approvalPolicy;

  /// Sandbox mode for command execution
  final CodexSandboxMode sandboxMode;

  /// Use full-auto mode (on-failure + workspace-write)
  final bool fullAuto;

  /// Bypass all approvals and sandbox (dangerous)
  final bool dangerouslyBypassAll;

  /// Model to use
  final String? model;

  /// Enable web search
  final bool enableWebSearch;

  /// Environment variables to set
  final Map<String, String>? environment;

  CodexSessionConfig({
    this.approvalPolicy = CodexApprovalPolicy.onRequest,
    this.sandboxMode = CodexSandboxMode.workspaceWrite,
    this.fullAuto = false,
    this.dangerouslyBypassAll = false,
    this.model,
    this.enableWebSearch = false,
    this.environment,
  });
}
```

#### codex_session.dart

```dart
/// A Codex CLI session
class CodexSession {
  /// Thread (session) identifier
  final String threadId;

  /// Stream of session events
  Stream<CodexEvent> get events => _eventController.stream;

  final StreamController<CodexEvent> _eventController;
  final String _cwd;
  final CodexSessionConfig _config;
  int _turnCounter;
  Process? _currentProcess;

  CodexSession._({
    required this.threadId,
    required StreamController<CodexEvent> eventController,
    required String cwd,
    required CodexSessionConfig config,
    required int initialTurnId,
  })  : _eventController = eventController,
        _cwd = cwd,
        _config = config,
        _turnCounter = initialTurnId;

  /// Send a follow-up message to the session
  ///
  /// Spawns a new Codex process with the `resume` subcommand.
  /// Events will be emitted to [events] stream as responses arrive.
  Future<void> send(String message) async {
    _turnCounter++;

    final args = _buildArgs(message, threadId, _config);

    _currentProcess = await Process.start('codex', args, workingDirectory: _cwd);

    _currentProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty || !line.trim().startsWith('{')) return;

      final json = jsonDecode(line) as Map<String, dynamic>;
      final event = CodexEvent.fromJson(json, threadId, _turnCounter);
      _eventController.add(event);
    });

    _currentProcess!.exitCode.then((code) {
      if (code != 0) {
        _eventController.addError(
          CodexProcessException('Codex process exited with code $code'),
        );
      }
    });
  }

  /// Cancel the current operation
  Future<void> cancel() async {
    _currentProcess?.kill(ProcessSignal.sigterm);
    await _eventController.close();
  }

  List<String> _buildArgs(String prompt, String threadId, CodexSessionConfig config) {
    return [
      'exec',
      '--output-jsonl',
      if (config.fullAuto) '--full-auto',
      if (config.dangerouslyBypassAll) '--dangerously-bypass-approvals-and-sandbox',
      if (!config.fullAuto && !config.dangerouslyBypassAll) ...[
        '-a', config.approvalPolicy.name.replaceAllMapped(
          RegExp(r'([A-Z])'), (m) => '-${m.group(1)!.toLowerCase()}'),
        '-s', config.sandboxMode.name.replaceAllMapped(
          RegExp(r'([A-Z])'), (m) => '-${m.group(1)!.toLowerCase()}'),
      ],
      if (config.model != null) ...['-m', config.model!],
      if (config.enableWebSearch) '--search',
      'resume', threadId,
      prompt,
    ];
  }
}

class CodexProcessException implements Exception {
  final String message;
  CodexProcessException(this.message);

  @override
  String toString() => 'CodexProcessException: $message';
}
```

#### codex_client.dart

```dart
/// Client for Codex CLI operations
class CodexClient {
  /// Working directory for this client
  final String cwd;

  int _turnCounter = 0;

  CodexClient({required this.cwd});

  /// Create a new Codex session
  ///
  /// Spawns a Codex process for the initial prompt.
  Future<CodexSession> createSession(
    String initialPrompt,
    CodexSessionConfig config,
  ) async {
    final args = _buildInitialArgs(initialPrompt, config);

    final process = await Process.start('codex', args, workingDirectory: cwd);
    final eventController = StreamController<CodexEvent>.broadcast();

    String? threadId;

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty || !line.trim().startsWith('{')) return;

      final json = jsonDecode(line) as Map<String, dynamic>;

      // Extract thread_id from first event
      if (threadId == null && json['type'] == 'thread.started') {
        threadId = json['thread_id'] as String;
      }

      final event = CodexEvent.fromJson(json, threadId ?? '', _turnCounter);
      eventController.add(event);
    });

    process.exitCode.then((code) {
      if (code != 0) {
        eventController.addError(
          CodexProcessException('Codex process exited with code $code'),
        );
      }
    });

    // Wait for thread.started event
    await eventController.stream.firstWhere((e) => e is CodexThreadStartedEvent);

    _turnCounter++;

    return CodexSession._(
      threadId: threadId!,
      eventController: eventController,
      cwd: cwd,
      config: config,
      initialTurnId: _turnCounter,
    );
  }

  /// Resume an existing session
  Future<CodexSession> resumeSession(
    String threadId,
    String prompt,
    CodexSessionConfig config,
  ) async {
    _turnCounter++;

    final eventController = StreamController<CodexEvent>.broadcast();

    final session = CodexSession._(
      threadId: threadId,
      eventController: eventController,
      cwd: cwd,
      config: config,
      initialTurnId: _turnCounter,
    );

    await session.send(prompt);

    return session;
  }

  /// List all sessions for this working directory
  Future<List<CodexSessionInfo>> listSessions() async {
    final sessionsDir = Directory('${Platform.environment['HOME']}/.codex/sessions');

    if (!await sessionsDir.exists()) {
      return [];
    }

    final sessions = <CodexSessionInfo>[];

    await for (final file in sessionsDir.list(recursive: true)) {
      if (file is! File || !file.path.endsWith('.jsonl')) continue;

      final info = await _parseSessionFile(file);
      if (info != null && info.cwd == cwd) {
        sessions.add(info);
      }
    }

    sessions.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));

    return sessions;
  }

  List<String> _buildInitialArgs(String prompt, CodexSessionConfig config) {
    return [
      'exec',
      '--output-jsonl',
      if (config.fullAuto) '--full-auto',
      if (config.dangerouslyBypassAll) '--dangerously-bypass-approvals-and-sandbox',
      if (!config.fullAuto && !config.dangerouslyBypassAll) ...[
        '-a', _formatEnumArg(config.approvalPolicy.name),
        '-s', _formatEnumArg(config.sandboxMode.name),
      ],
      if (config.model != null) ...['-m', config.model!],
      if (config.enableWebSearch) '--search',
      prompt,
    ];
  }

  String _formatEnumArg(String camelCase) {
    return camelCase.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (m) => '-${m.group(1)!.toLowerCase()}',
    );
  }

  Future<CodexSessionInfo?> _parseSessionFile(File file) async {
    // Implementation reads first line to extract metadata
    // Parses cwd from environment_context in user messages
  }
}
```

---

## 5. Gemini CLI Adapter

### 5.1 Overview

Gemini CLI uses a **process-per-turn model** similar to Codex. Each user message spawns a new process. Sessions are restored via the `--resume` flag.

### 5.2 Types

#### gemini_types.dart

```dart
/// Gemini approval modes
enum GeminiApprovalMode {
  /// Prompt for each tool (default)
  defaultMode,

  /// Auto-approve file edits only
  autoEdit,

  /// Auto-approve everything (YOLO)
  yolo,
}

/// Information about a stored Gemini session
@JsonSerializable()
class GeminiSessionInfo {
  final String sessionId;
  final String projectHash;
  final DateTime startTime;
  final DateTime lastUpdated;
  final int messageCount;

  GeminiSessionInfo({
    required this.sessionId,
    required this.projectHash,
    required this.startTime,
    required this.lastUpdated,
    required this.messageCount,
  });

  factory GeminiSessionInfo.fromJson(Map<String, dynamic> json) =>
      _$GeminiSessionInfoFromJson(json);
  Map<String, dynamic> toJson() => _$GeminiSessionInfoToJson(this);
}

/// Token/usage statistics
@JsonSerializable()
class GeminiStats {
  final int totalTokens;
  final int inputTokens;
  final int outputTokens;
  final int durationMs;
  final int toolCalls;

  GeminiStats({
    required this.totalTokens,
    required this.inputTokens,
    required this.outputTokens,
    required this.durationMs,
    required this.toolCalls,
  });

  factory GeminiStats.fromJson(Map<String, dynamic> json) =>
      _$GeminiStatsFromJson(json);
  Map<String, dynamic> toJson() => _$GeminiStatsToJson(this);
}

/// Tool use parameters
@JsonSerializable()
class GeminiToolUse {
  final String toolName;
  final String toolId;
  final Map<String, dynamic> parameters;

  GeminiToolUse({
    required this.toolName,
    required this.toolId,
    required this.parameters,
  });

  factory GeminiToolUse.fromJson(Map<String, dynamic> json) =>
      _$GeminiToolUseFromJson(json);
  Map<String, dynamic> toJson() => _$GeminiToolUseToJson(this);
}

/// Tool result
@JsonSerializable()
class GeminiToolResult {
  final String toolId;
  final String status; // "success", "error"
  final String? output;
  final Map<String, dynamic>? error;

  GeminiToolResult({
    required this.toolId,
    required this.status,
    this.output,
    this.error,
  });

  factory GeminiToolResult.fromJson(Map<String, dynamic> json) =>
      _$GeminiToolResultFromJson(json);
  Map<String, dynamic> toJson() => _$GeminiToolResultToJson(this);
}
```

#### gemini_events.dart

```dart
/// Base class for all Gemini streaming events
sealed class GeminiEvent {
  final String sessionId;
  final int turnId;
  final DateTime timestamp;

  const GeminiEvent({
    required this.sessionId,
    required this.turnId,
    required this.timestamp,
  });

  factory GeminiEvent.fromJson(Map<String, dynamic> json, String sessionId, int turnId) {
    final type = json['type'] as String;
    final timestamp = DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now();

    return switch (type) {
      'init' => GeminiInitEvent.fromJson(json, turnId),
      'message' => GeminiMessageEvent.fromJson(json, sessionId, turnId),
      'tool_use' => GeminiToolUseEvent.fromJson(json, sessionId, turnId),
      'tool_result' => GeminiToolResultEvent.fromJson(json, sessionId, turnId),
      'result' => GeminiResultEvent.fromJson(json, sessionId, turnId),
      'error' => GeminiErrorEvent.fromJson(json, sessionId, turnId),
      'retry' => GeminiRetryEvent.fromJson(json, sessionId, turnId),
      _ => GeminiUnknownEvent(sessionId: sessionId, turnId: turnId, timestamp: timestamp, type: type, data: json),
    };
  }
}

/// Session initialization event
@JsonSerializable()
class GeminiInitEvent extends GeminiEvent {
  final String model;

  GeminiInitEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.model,
  });

  factory GeminiInitEvent.fromJson(Map<String, dynamic> json, int turnId) =>
      GeminiInitEvent(
        sessionId: json['session_id'] as String,
        turnId: turnId,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        model: json['model'] as String? ?? '',
      );
}

/// Message event (user or assistant)
@JsonSerializable()
class GeminiMessageEvent extends GeminiEvent {
  final String role; // "user", "assistant"
  final String content;
  final bool delta; // true if streaming partial content

  GeminiMessageEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.role,
    required this.content,
    required this.delta,
  });

  factory GeminiMessageEvent.fromJson(Map<String, dynamic> json, String sessionId, int turnId) =>
      GeminiMessageEvent(
        sessionId: sessionId,
        turnId: turnId,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        role: json['role'] as String? ?? '',
        content: json['content'] as String? ?? '',
        delta: json['delta'] as bool? ?? false,
      );
}

/// Tool use event
@JsonSerializable()
class GeminiToolUseEvent extends GeminiEvent {
  final GeminiToolUse toolUse;

  GeminiToolUseEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.toolUse,
  });

  factory GeminiToolUseEvent.fromJson(Map<String, dynamic> json, String sessionId, int turnId) =>
      GeminiToolUseEvent(
        sessionId: sessionId,
        turnId: turnId,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        toolUse: GeminiToolUse(
          toolName: json['tool_name'] as String? ?? '',
          toolId: json['tool_id'] as String? ?? '',
          parameters: json['parameters'] as Map<String, dynamic>? ?? {},
        ),
      );
}

/// Tool result event
@JsonSerializable()
class GeminiToolResultEvent extends GeminiEvent {
  final GeminiToolResult toolResult;

  GeminiToolResultEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.toolResult,
  });

  factory GeminiToolResultEvent.fromJson(Map<String, dynamic> json, String sessionId, int turnId) =>
      GeminiToolResultEvent(
        sessionId: sessionId,
        turnId: turnId,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        toolResult: GeminiToolResult(
          toolId: json['tool_id'] as String? ?? '',
          status: json['status'] as String? ?? '',
          output: json['output'] as String?,
          error: json['error'] as Map<String, dynamic>?,
        ),
      );
}

/// Session result event
@JsonSerializable()
class GeminiResultEvent extends GeminiEvent {
  final String status; // "success", "error", "cancelled"
  final GeminiStats? stats;
  final Map<String, dynamic>? error;

  GeminiResultEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.status,
    this.stats,
    this.error,
  });

  factory GeminiResultEvent.fromJson(Map<String, dynamic> json, String sessionId, int turnId) =>
      GeminiResultEvent(
        sessionId: sessionId,
        turnId: turnId,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        status: json['status'] as String? ?? 'unknown',
        stats: json['stats'] != null
            ? GeminiStats.fromJson(json['stats'] as Map<String, dynamic>)
            : null,
        error: json['error'] as Map<String, dynamic>?,
      );
}

/// Error event
@JsonSerializable()
class GeminiErrorEvent extends GeminiEvent {
  final String code;
  final String message;

  GeminiErrorEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.code,
    required this.message,
  });

  factory GeminiErrorEvent.fromJson(Map<String, dynamic> json, String sessionId, int turnId) {
    final error = json['error'] as Map<String, dynamic>? ?? {};
    return GeminiErrorEvent(
      sessionId: sessionId,
      turnId: turnId,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      code: error['code'] as String? ?? 'UNKNOWN',
      message: error['message'] as String? ?? 'Unknown error',
    );
  }
}

/// Retry event (transient failure handling)
@JsonSerializable()
class GeminiRetryEvent extends GeminiEvent {
  final int attempt;
  final int maxAttempts;
  final int delayMs;

  GeminiRetryEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.attempt,
    required this.maxAttempts,
    required this.delayMs,
  });

  factory GeminiRetryEvent.fromJson(Map<String, dynamic> json, String sessionId, int turnId) =>
      GeminiRetryEvent(
        sessionId: sessionId,
        turnId: turnId,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
        attempt: json['attempt'] as int? ?? 0,
        maxAttempts: json['max_attempts'] as int? ?? 0,
        delayMs: json['delay_ms'] as int? ?? 0,
      );
}

/// Unknown event type
class GeminiUnknownEvent extends GeminiEvent {
  final String type;
  final Map<String, dynamic> data;

  GeminiUnknownEvent({
    required super.sessionId,
    required super.turnId,
    required super.timestamp,
    required this.type,
    required this.data,
  });
}
```

#### gemini_config.dart

```dart
/// Configuration for a Gemini session
class GeminiSessionConfig {
  /// Approval mode for tool execution
  final GeminiApprovalMode approvalMode;

  /// Enable sandbox mode
  final bool sandbox;

  /// Custom sandbox image
  final String? sandboxImage;

  /// Model to use (e.g., "gemini-2.0-flash-exp")
  final String? model;

  /// Enable debug output
  final bool debug;

  GeminiSessionConfig({
    this.approvalMode = GeminiApprovalMode.defaultMode,
    this.sandbox = false,
    this.sandboxImage,
    this.model,
    this.debug = false,
  });
}
```

#### gemini_session.dart

```dart
/// A Gemini CLI session
class GeminiSession {
  /// Session identifier
  final String sessionId;

  /// Stream of session events
  Stream<GeminiEvent> get events => _eventController.stream;

  final StreamController<GeminiEvent> _eventController;
  final String _cwd;
  final GeminiSessionConfig _config;
  int _turnCounter;
  Process? _currentProcess;

  GeminiSession._({
    required this.sessionId,
    required StreamController<GeminiEvent> eventController,
    required String cwd,
    required GeminiSessionConfig config,
    required int initialTurnId,
  })  : _eventController = eventController,
        _cwd = cwd,
        _config = config,
        _turnCounter = initialTurnId;

  /// Send a follow-up message to the session
  ///
  /// Spawns a new Gemini process with the `--resume` flag.
  Future<void> send(String message) async {
    _turnCounter++;

    final args = _buildArgs(message, sessionId, _config);

    _currentProcess = await Process.start('gemini', args, workingDirectory: _cwd);

    _currentProcess!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty || !line.trim().startsWith('{')) return;

      final json = jsonDecode(line) as Map<String, dynamic>;
      final event = GeminiEvent.fromJson(json, sessionId, _turnCounter);
      _eventController.add(event);
    });

    _currentProcess!.exitCode.then((code) {
      if (code != 0) {
        _eventController.addError(
          GeminiProcessException('Gemini process exited with code $code'),
        );
      }
    });
  }

  /// Cancel the current operation
  Future<void> cancel() async {
    _currentProcess?.kill(ProcessSignal.sigterm);
    await _eventController.close();
  }

  List<String> _buildArgs(String prompt, String sessionId, GeminiSessionConfig config) {
    return [
      '-p', prompt,
      '--output-format', 'stream-json',
      '--resume', sessionId,
      if (config.approvalMode == GeminiApprovalMode.yolo) '-y',
      if (config.approvalMode == GeminiApprovalMode.autoEdit) '--auto-edit',
      if (config.sandbox) '--sandbox',
      if (config.sandboxImage != null) ...['--sandbox-image', config.sandboxImage!],
      if (config.model != null) ...['--model', config.model!],
      if (config.debug) '--debug',
    ];
  }
}

class GeminiProcessException implements Exception {
  final String message;
  GeminiProcessException(this.message);

  @override
  String toString() => 'GeminiProcessException: $message';
}
```

#### gemini_client.dart

```dart
/// Client for Gemini CLI operations
class GeminiClient {
  /// Working directory for this client
  final String cwd;

  int _turnCounter = 0;

  GeminiClient({required this.cwd});

  /// Create a new Gemini session
  Future<GeminiSession> createSession(
    String initialPrompt,
    GeminiSessionConfig config,
  ) async {
    final args = _buildInitialArgs(initialPrompt, config);

    final process = await Process.start('gemini', args, workingDirectory: cwd);
    final eventController = StreamController<GeminiEvent>.broadcast();

    String? sessionId;

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty || !line.trim().startsWith('{')) return;

      final json = jsonDecode(line) as Map<String, dynamic>;

      // Extract session_id from init event
      if (sessionId == null && json['type'] == 'init') {
        sessionId = json['session_id'] as String;
      }

      final event = GeminiEvent.fromJson(json, sessionId ?? '', _turnCounter);
      eventController.add(event);
    });

    process.exitCode.then((code) {
      if (code != 0) {
        eventController.addError(
          GeminiProcessException('Gemini process exited with code $code'),
        );
      }
    });

    // Wait for init event
    await eventController.stream.firstWhere((e) => e is GeminiInitEvent);

    _turnCounter++;

    return GeminiSession._(
      sessionId: sessionId!,
      eventController: eventController,
      cwd: cwd,
      config: config,
      initialTurnId: _turnCounter,
    );
  }

  /// Resume an existing session
  Future<GeminiSession> resumeSession(
    String sessionId,
    String prompt,
    GeminiSessionConfig config,
  ) async {
    _turnCounter++;

    final eventController = StreamController<GeminiEvent>.broadcast();

    final session = GeminiSession._(
      sessionId: sessionId,
      eventController: eventController,
      cwd: cwd,
      config: config,
      initialTurnId: _turnCounter,
    );

    await session.send(prompt);

    return session;
  }

  /// List all sessions for this working directory
  ///
  /// Uses the `gemini --list-sessions` CLI command.
  Future<List<GeminiSessionInfo>> listSessions() async {
    // Option 1: Parse CLI output
    final result = await Process.run(
      'gemini',
      ['--list-sessions'],
      workingDirectory: cwd,
    );

    if (result.exitCode != 0) {
      return [];
    }

    // Parse text output from CLI
    return _parseListSessionsOutput(result.stdout as String);
  }

  /// List sessions by reading from disk
  Future<List<GeminiSessionInfo>> listSessionsFromDisk() async {
    final tmpDir = Directory('${Platform.environment['HOME']}/.gemini/tmp');

    if (!await tmpDir.exists()) {
      return [];
    }

    final sessions = <GeminiSessionInfo>[];

    await for (final projectDir in tmpDir.list()) {
      if (projectDir is! Directory) continue;

      final chatsDir = Directory('${projectDir.path}/chats');
      if (!await chatsDir.exists()) continue;

      await for (final file in chatsDir.list()) {
        if (file is! File || !file.path.endsWith('.json')) continue;

        final info = await _parseSessionFile(file);
        if (info != null) {
          sessions.add(info);
        }
      }
    }

    sessions.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));

    return sessions;
  }

  List<String> _buildInitialArgs(String prompt, GeminiSessionConfig config) {
    return [
      '-p', prompt,
      '--output-format', 'stream-json',
      if (config.approvalMode == GeminiApprovalMode.yolo) '-y',
      if (config.approvalMode == GeminiApprovalMode.autoEdit) '--auto-edit',
      if (config.sandbox) '--sandbox',
      if (config.sandboxImage != null) ...['--sandbox-image', config.sandboxImage!],
      if (config.model != null) ...['--model', config.model!],
      if (config.debug) '--debug',
    ];
  }

  List<GeminiSessionInfo> _parseListSessionsOutput(String output) {
    // Parse the text output from gemini --list-sessions
    // Format varies, implementation parses available sessions
  }

  Future<GeminiSessionInfo?> _parseSessionFile(File file) async {
    // Read JSON file and extract session metadata
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;

    return GeminiSessionInfo(
      sessionId: json['sessionId'] as String,
      projectHash: json['projectHash'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      messageCount: (json['messages'] as List<dynamic>).length,
    );
  }
}
```

---

## 6. Implementation Notes

### 6.1 MCP Permission Server for Claude

The Claude adapter includes an internal MCP server for permission delegation:

```dart
// claude_permission_server.dart

import 'package:mcp_dart/mcp_dart.dart';

class ClaudePermissionServer {
  final ClaudePermissionHandler _handler;
  late final McpServer _server;

  ClaudePermissionServer(this._handler);

  Future<void> start() async {
    _server = McpServer(
      name: 'claude_adapter',
      version: '1.0.0',
    );

    _server.addTool(
      Tool(
        name: 'handle_permission',
        description: 'Handle permission request from Claude',
        inputSchema: {
          'type': 'object',
          'properties': {
            'tool_name': {'type': 'string'},
            'tool_input': {'type': 'object'},
            'session_id': {'type': 'string'},
            'turn_id': {'type': 'integer'},
          },
          'required': ['tool_name', 'tool_input'],
        },
      ),
      (arguments) async {
        final request = ClaudeToolPermissionRequest(
          toolName: arguments['tool_name'] as String,
          toolInput: arguments['tool_input'] as Map<String, dynamic>,
          sessionId: arguments['session_id'] as String? ?? '',
          turnId: arguments['turn_id'] as int? ?? 0,
        );

        final response = await _handler(request);

        return {
          'behavior': response.behavior.name,
          if (response.updatedInput != null) 'updatedInput': response.updatedInput,
          if (response.message != null) 'message': response.message,
        };
      },
    );

    await _server.connect(StdioTransport());
  }

  Future<void> stop() async {
    await _server.close();
  }
}
```

### 6.2 Error Handling

All adapters propagate errors as exceptions:

- `ClaudeProcessException`: Claude process errors
- `CodexProcessException`: Codex process errors
- `GeminiProcessException`: Gemini process errors

Consumers should handle these at the call site.

### 6.3 Stream Lifecycle

- Events stream starts when session is created
- Events include `turnId` for client-side grouping
- Stream closes when:
  - `cancel()` is called
  - Process exits (normal or error)
  - For Claude: stdin is closed (EOF sent)

### 6.4 File Parsing for Session Listing

Each adapter implements session file parsing specific to its CLI:

- **Claude**: Parse JSONL, extract metadata from `user`/`assistant` type lines
- **Codex**: Parse JSONL, extract metadata from first line and `environment_context`
- **Gemini**: Parse JSON (not JSONL), extract top-level metadata fields

---

*End of Design Specification v1.0.0*
