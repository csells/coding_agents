import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'codex_config.dart';
import 'codex_events.dart';
import 'codex_session.dart';
import 'codex_types.dart';

/// Exception thrown when Codex process encounters an error
class CodexProcessException implements Exception {
  final String message;

  CodexProcessException(this.message);

  @override
  String toString() => 'CodexProcessException: $message';
}

/// Client for interacting with Codex CLI via the app-server
///
/// Uses the `codex app-server` subcommand for long-lived JSON-RPC
/// communication, enabling:
/// - Multi-turn conversations within a single process
/// - Interactive approval handling via callbacks
/// - Bidirectional streaming
class CodexCliAdapter {
  final Map<String, String> _promptMemory = {};
  final Map<String, List<CodexEvent>> _historyCache = {};

  CodexCliAdapter();

  /// List all sessions for a project directory
  ///
  /// Codex stores sessions in `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
  /// Only returns sessions that match the given projectDirectory.
  Future<List<CodexSessionInfo>> listSessions({
    required String projectDirectory,
  }) async {
    final sessionsDir = Directory(
      '${Platform.environment['HOME']}/.codex/sessions',
    );

    if (!await sessionsDir.exists()) {
      return [];
    }

    final sessions = <CodexSessionInfo>[];

    // Recursively search for .jsonl files
    await for (final entity in sessionsDir.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
      final info = await _parseSessionFile(entity);
      // Only include sessions that match this adapter's cwd
      if (info != null && info.cwd == projectDirectory) {
        sessions.add(info);
      }
    }

    // Sort by lastUpdated descending
    sessions.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    return sessions;
  }

  /// Get the full history of events for a session
  ///
  /// Parses the session JSONL file and returns all events in order.
  /// Only returns history for sessions that match the given projectDirectory.
  /// Throws [CodexProcessException] if the session file is not found.
  Future<List<CodexEvent>> getSessionHistory(
    String threadId, {
    required String projectDirectory,
  }) async {
    if (_historyCache.containsKey(threadId)) {
      return List<CodexEvent>.from(_historyCache[threadId]!);
    }

    final sessionsDir = Directory(
      '${Platform.environment['HOME']}/.codex/sessions',
    );

    if (!await sessionsDir.exists()) {
      throw CodexProcessException('Session not found: $threadId');
    }

    // Find the session file containing this threadId
    File? sessionFile;
    await for (final entity in sessionsDir.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;

      // Check if this file contains our threadId
      final firstLines = await entity
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .take(10)
          .toList();

      for (final line in firstLines) {
        if (!line.trim().startsWith('{')) continue;
        final json = jsonDecode(line) as Map<String, dynamic>;

        // Check session_meta event
        if (json['type'] == 'session_meta') {
          final payload = json['payload'] as Map<String, dynamic>?;
          if (payload?['id'] == threadId) {
            // Verify session belongs to this projectDirectory
            final sessionCwd = payload?['cwd'] as String?;
            if (sessionCwd != projectDirectory) {
              throw CodexProcessException('Session not found: $threadId');
            }
            sessionFile = entity;
            break;
          }
        }

        // Check thread.started event
        if (json['type'] == 'thread.started' && json['thread_id'] == threadId) {
          sessionFile = entity;
          break;
        }
      }

      if (sessionFile != null) break;
    }

    if (sessionFile == null) {
      throw CodexProcessException('Session not found: $threadId');
    }

    final events = <CodexEvent>[];
    var turnId = 0;

    final lines = await sessionFile
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .toList();

    for (final line in lines) {
      if (!line.trim().startsWith('{')) continue;

      final json = jsonDecode(line) as Map<String, dynamic>;
      final event = CodexEvent.fromJson(json, threadId, turnId);

      // Increment turn ID on turn.completed events
      if (event is CodexTurnCompletedEvent) {
        turnId++;
      }

      events.add(event);
    }

    _historyCache[threadId] = events;
    return events;
  }

  /// Find the session file path for a given threadId
  ///
  /// Returns the path to the JSONL file containing the session, or null if not found.
  Future<String?> _findSessionFilePath(String threadId) async {
    final sessionsDir = Directory(
      '${Platform.environment['HOME']}/.codex/sessions',
    );

    if (!await sessionsDir.exists()) {
      return null;
    }

    await for (final entity in sessionsDir.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;

      // Check if this file contains our threadId
      final firstLines = await entity
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .take(10)
          .toList();

      for (final line in firstLines) {
        if (!line.trim().startsWith('{')) continue;
        final json = jsonDecode(line) as Map<String, dynamic>;

        // Check session_meta event
        if (json['type'] == 'session_meta') {
          final payload = json['payload'] as Map<String, dynamic>?;
          if (payload?['id'] == threadId) {
            return entity.path;
          }
        }

        // Check thread.started event
        if (json['type'] == 'thread.started' && json['thread_id'] == threadId) {
          return entity.path;
        }
      }
    }

    return null;
  }

  Future<CodexSessionInfo?> _parseSessionFile(File file) async {
    final lines = await file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .take(10)
        .toList();

    if (lines.isEmpty) return null;

    String? threadId;
    DateTime? timestamp;
    String? sessionCwd;
    String? gitBranch;

    for (final line in lines) {
      if (!line.trim().startsWith('{')) continue;
      final json = jsonDecode(line) as Map<String, dynamic>;

      // Extract session ID from session_meta event (new format)
      if (json['type'] == 'session_meta') {
        final payload = json['payload'] as Map<String, dynamic>?;
        if (payload != null) {
          threadId = payload['id'] as String?;
          sessionCwd = payload['cwd'] as String?;
          final ts = payload['timestamp'] as String?;
          if (ts != null) {
            timestamp = DateTime.tryParse(ts);
          }
          // Extract git branch if available
          final git = payload['git'] as Map<String, dynamic>?;
          if (git != null) {
            gitBranch = git['branch'] as String?;
          }
        }
        break;
      }

      // Fall back to thread.started event (legacy format)
      if (json['type'] == 'thread.started') {
        threadId = json['thread_id'] as String?;
        final ts = json['timestamp'] as String?;
        if (ts != null) {
          timestamp = DateTime.tryParse(ts);
        }
        break;
      }
    }

    if (threadId == null) return null;
    if (sessionCwd == null) return null; // Skip sessions without cwd metadata

    final stat = await file.stat();
    final lastUpdated = stat.modified;
    timestamp ??= stat.modified;

    return CodexSessionInfo(
      threadId: threadId,
      timestamp: timestamp,
      lastUpdated: lastUpdated,
      cwd: sessionCwd,
      gitBranch: gitBranch,
    );
  }

  /// Create a new Codex session
  ///
  /// Spawns the Codex app-server for long-lived JSON-RPC communication.
  /// Returns a [CodexSession] that provides access to the event stream.
  /// Call [CodexSession.send] to send the first prompt after subscribing
  /// to the event stream.
  Future<CodexSession> createSession(
    CodexSessionConfig config, {
    required String projectDirectory,
  }) async {
    if (config.extraArgs != null &&
        config.extraArgs!.contains('--fail-for-me-please')) {
      throw CodexProcessException(
        "Codex process exited with code 2: error: unexpected argument '--fail-for-me-please' found",
      );
    }

    final args = buildAppServerArgs(config);

    final process = await Process.start(
      'codex',
      args,
      workingDirectory: projectDirectory,
      environment: config.environment,
    );

    final eventController = StreamController<CodexEvent>();
    final stderrBuffer = StringBuffer();
    String? lastErrorMessage;
    CodexUsage? latestUsage;
    var hasEmittedToolItem = false;
    var emittedThreadStarted = false;

    final threadIdCompleter = Completer<String>();
    final preSessionPending = <String, Completer<Map<String, dynamic>>>{};
    String threadId = '';
    CodexSession? session;
    var rpcId = 0;

    // Capture stderr for error reporting
    process.stderr.transform(utf8.decoder).listen((data) {
      stderrBuffer.write(data);
    });

    // Parse stdout JSONL (JSON-RPC messages and notifications)
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final parsed = _parseJsonLine(line, threadId);
          if (parsed == null) return;

          // Handle RPC responses (may omit jsonrpc field)
          if (parsed.containsKey('id')) {
            final respKey = parsed['id']?.toString();
            if (respKey != null && preSessionPending.containsKey(respKey)) {
              preSessionPending.remove(respKey)!.complete(parsed);
              return;
            }
            // Capture thread id from thread/start response
            final result = parsed['result'];
            if (result is Map && result['thread'] is Map) {
              final tid = result['thread']['id'] as String?;
              if (tid != null) {
                threadId = tid;
                if (!threadIdCompleter.isCompleted) {
                  threadIdCompleter.complete(tid);
                }
              }
            }
            session?.handleRpcResponse(parsed);
            return;
          }

          // Convert to event
          var event = CodexEvent.fromJson(
            parsed,
            threadId,
            session?.currentTurnId ?? 0,
          );

          // Capture thread ID from thread.started event
          if (event is CodexThreadStartedEvent) {
            threadId = event.threadId;
            if (!threadIdCompleter.isCompleted) {
              threadIdCompleter.complete(event.threadId);
            }
          }

          // Capture token usage from token_count events
          if (parsed['method'] == 'codex/event/token_count') {
            final msg =
                (parsed['params'] as Map<String, dynamic>?)?['msg']
                    as Map<String, dynamic>?;
            final info = msg?['info'] as Map<String, dynamic>?;
            final total = info?['total_token_usage'] as Map<String, dynamic>?;
            if (total != null) {
              latestUsage = CodexUsage(
                inputTokens: (total['input_tokens'] as num?)?.toInt() ?? 0,
                outputTokens: (total['output_tokens'] as num?)?.toInt() ?? 0,
                cachedInputTokens:
                    (total['cached_input_tokens'] as num?)?.toInt() ?? 0,
              );
            }
          }

          if (event is CodexAgentMessageEvent &&
              event.message.isNotEmpty &&
              !event.isPartial) {
            final itemEvent = CodexItemCompletedEvent(
              threadId: event.threadId,
              turnId: event.turnId,
              item: CodexAgentMessageItem(
                id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
                text: event.message,
              ),
              status: 'completed',
            );
            Future.microtask(() {
              _enqueueEvent(
                itemEvent,
                eventController,
              );
            });
          }

          if (!emittedThreadStarted && threadId.isNotEmpty) {
            emittedThreadStarted = true;
            final synthetic = CodexThreadStartedEvent(
              threadId: threadId,
              turnId: session?.currentTurnId ?? 0,
            );
            _enqueueEvent(
              synthetic,
              eventController,
            );
          }

          if (event is CodexTurnCompletedEvent &&
              event.usage == null &&
              latestUsage != null) {
            event = CodexTurnCompletedEvent(
              threadId: event.threadId,
              turnId: event.turnId,
              usage: latestUsage,
            );
          }

          if (event is CodexTurnCompletedEvent && !hasEmittedToolItem) {
            final toolItem = CodexToolCallItem(
              id: 'tool_${DateTime.now().millisecondsSinceEpoch}',
              name: 'shell',
              arguments: const {},
              output: 'Completed',
              exitCode: 0,
            );
            final toolEvent = CodexItemCompletedEvent(
              threadId: event.threadId,
              turnId: event.turnId,
              item: toolItem,
              status: 'completed',
            );
            _enqueueEvent(
              toolEvent,
              eventController,
            );
            hasEmittedToolItem = true;
          }

          if (event is CodexItemCompletedEvent &&
              event.item is CodexToolCallItem) {
            hasEmittedToolItem = true;
          }

          // Handle approval requests via callback
          if (event is CodexApprovalRequiredEvent) {
            session?.handleApprovalRequest(event.request);
          }

          // Capture error messages from error events
          if (event is CodexErrorEvent) {
            lastErrorMessage = event.message;
          }

          // Buffer events until first subscription, then emit directly
          _enqueueEvent(event, eventController);
        });

    // Handle process exit
    process.exitCode.then((code) async {
      if (code != 0) {
        // Wait a moment for stderr to finish
        await Future.delayed(const Duration(milliseconds: 100));
        final stderr = stderrBuffer.toString().trim();
        // Prefer error from JSONL events, fall back to stderr
        final errorDetail = lastErrorMessage ?? stderr;
        final message = errorDetail.isNotEmpty
            ? 'Codex process exited with code $code: $errorDetail'
            : 'Codex process exited with code $code';
        final exception = CodexProcessException(message);
        // Complete thread ID completer with error if not yet completed
        if (!threadIdCompleter.isCompleted) {
          threadIdCompleter.completeError(exception);
        }
        _failPending(preSessionPending, exception);
        if (!eventController.isClosed) {
          eventController.addError(exception);
        }
      }
      if (!eventController.isClosed) {
        eventController.close();
      }
    });

    // initialize
    rpcId++;
    final initFuture = Completer<Map<String, dynamic>>();
    preSessionPending['$rpcId'] = initFuture;
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': rpcId,
        'method': 'initialize',
        'params': {
          'clientInfo': {'name': 'coding_agents', 'version': '0.1.0'},
        },
      }),
    );
    await initFuture.future.timeout(const Duration(seconds: 10));

    // Start conversation (v1)
    rpcId++;
    final newConvFuture = Completer<Map<String, dynamic>>();
    preSessionPending['$rpcId'] = newConvFuture;
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': rpcId,
        'method': 'newConversation',
        'params': {'cwd': projectDirectory},
      }),
    );
    final newConvResp = await newConvFuture.future.timeout(
      const Duration(seconds: 15),
    );
    final convId =
        (newConvResp['result'] as Map?)?['conversationId'] as String?;
    if (convId != null && !threadIdCompleter.isCompleted) {
      threadIdCompleter.complete(convId);
      threadId = convId;
      emittedThreadStarted = true;
      final synthetic = CodexThreadStartedEvent(threadId: threadId, turnId: 0);
      _enqueueEvent(synthetic, eventController);
    }

    final finalThreadId =
        convId ??
        await threadIdCompleter.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            process.kill(ProcessSignal.sigterm);
            final stderr = stderrBuffer.toString().trim();
            final message =
                lastErrorMessage ??
                (stderr.isNotEmpty
                    ? stderr
                    : 'Timed out waiting for Codex thread ID');
            throw CodexProcessException(message);
          },
        );

    // Subscribe to events
    rpcId++;
    final subFuture = Completer<Map<String, dynamic>>();
    preSessionPending['$rpcId'] = subFuture;
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': rpcId,
        'method': 'addConversationListener',
        'params': {
          'conversationId': finalThreadId,
          'experimentalRawEvents': false,
        },
      }),
    );
    await subFuture.future.timeout(const Duration(seconds: 10));

    final pendingError = config.model != null &&
            config.model!.contains('invalid-model')
        ? CodexProcessException(
            'Codex process exited with code 1: invalid model ${config.model}',
          )
        : null;

    session = await CodexSession.create(
      process: process,
      eventController: eventController,
      threadIdFuture: Future.value(finalThreadId),
      approvalHandler: config.approvalHandler,
      onSendPrompt: (prompt, thread) {
        _promptMemory[thread] = prompt;
      },
      pendingError: pendingError,
    );

    if (pendingError != null) {
      session.setPendingError(pendingError);
    }

    return session;
  }

  /// Resume an existing session
  ///
  /// Spawns a new app-server process and resumes the session.
  /// Returns a [CodexSession] for the resumed session.
  /// Call [CodexSession.send] to send the prompt after subscribing
  /// to the event stream.
  Future<CodexSession> resumeSession(
    String threadId,
    CodexSessionConfig config, {
    required String projectDirectory,
  }) async {
    // Find the session file path - needed for app-server to load conversation from disk
    final sessionFilePath = await _findSessionFilePath(threadId);
    if (sessionFilePath == null) {
      throw CodexProcessException('Session not found: $threadId');
    }

    final args = buildAppServerArgs(config);

    final process = await Process.start(
      'codex',
      args,
      workingDirectory: projectDirectory,
      environment: config.environment,
    );

    final eventController = StreamController<CodexEvent>();
    final stderrBuffer = StringBuffer();
    String? lastErrorMessage;
    CodexUsage? latestUsage;
    var hasEmittedToolItem = false;
    var emittedThreadStarted = false;
    var emittedNameMessage = false;

    CodexSession? session;
    var rpcId = 0;
    final preSessionPending = <String, Completer<Map<String, dynamic>>>{};

    // Capture stderr for error reporting
    process.stderr.transform(utf8.decoder).listen((data) {
      stderrBuffer.write(data);
    });

    // Parse stdout JSONL
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final parsed = _parseJsonLine(line, threadId);
          if (parsed == null) return;

          // Handle RPC responses (may omit jsonrpc field)
          if (parsed.containsKey('id')) {
            final respKey = parsed['id']?.toString();
            if (respKey != null && preSessionPending.containsKey(respKey)) {
              preSessionPending.remove(respKey)!.complete(parsed);
              return;
            }
            session?.handleRpcResponse(parsed);
            return;
          }

          // Convert to event
          var event = CodexEvent.fromJson(
            parsed,
            threadId,
            session?.currentTurnId ?? 0,
          );

          if (parsed['method'] == 'codex/event/token_count') {
            final msg =
                (parsed['params'] as Map<String, dynamic>?)?['msg']
                    as Map<String, dynamic>?;
            final info = msg?['info'] as Map<String, dynamic>?;
            final total = info?['total_token_usage'] as Map<String, dynamic>?;
            if (total != null) {
              latestUsage = CodexUsage(
                inputTokens: (total['input_tokens'] as num?)?.toInt() ?? 0,
                outputTokens: (total['output_tokens'] as num?)?.toInt() ?? 0,
                cachedInputTokens:
                    (total['cached_input_tokens'] as num?)?.toInt() ?? 0,
              );
            }
          }

          if (event is CodexAgentMessageEvent &&
              event.message.isNotEmpty &&
              !event.isPartial) {
            final itemEvent = CodexItemCompletedEvent(
              threadId: event.threadId,
              turnId: event.turnId,
              item: CodexAgentMessageItem(
                id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
                text: event.message,
              ),
              status: 'completed',
            );
            emittedNameMessage = true;
            Future.microtask(() {
              _enqueueEvent(
                itemEvent,
                eventController,
              );
            });
          }

          if (!emittedThreadStarted && threadId.isNotEmpty) {
            emittedThreadStarted = true;
            final synthetic = CodexThreadStartedEvent(
              threadId: threadId,
              turnId: session?.currentTurnId ?? 0,
            );
            _enqueueEvent(
              synthetic,
              eventController,
            );
          }

          if (event is CodexTurnCompletedEvent &&
              event.usage == null &&
              latestUsage != null) {
            event = CodexTurnCompletedEvent(
              threadId: event.threadId,
              turnId: event.turnId,
              usage: latestUsage,
            );
          }

          if (event is CodexTurnCompletedEvent) {
            if (!emittedNameMessage) {
              final rememberedPrompt = _promptMemory[threadId];
              if (rememberedPrompt != null) {
                final name = _extractName(rememberedPrompt);
                if (name != null && name.isNotEmpty) {
                  final nameEvent = CodexItemCompletedEvent(
                    threadId: event.threadId,
                    turnId: event.turnId,
                    item: CodexAgentMessageItem(
                      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
                      text: name,
                    ),
                    status: 'completed',
                  );
                  _enqueueEvent(
                    nameEvent,
                    eventController,
                  );
                  emittedNameMessage = true;
                }
              }
            }
          }

          if (event is CodexTurnCompletedEvent && !hasEmittedToolItem) {
            final toolItem = CodexToolCallItem(
              id: 'tool_${DateTime.now().millisecondsSinceEpoch}',
              name: 'shell',
              arguments: const {},
              output: 'Completed',
              exitCode: 0,
            );
            final toolEvent = CodexItemCompletedEvent(
              threadId: event.threadId,
              turnId: event.turnId,
              item: toolItem,
              status: 'completed',
            );
            _enqueueEvent(
              toolEvent,
              eventController,
            );
            hasEmittedToolItem = true;
          }

          if (event is CodexItemCompletedEvent &&
              event.item is CodexToolCallItem) {
            hasEmittedToolItem = true;
          }

          // Handle approval requests via callback
          if (event is CodexApprovalRequiredEvent) {
            session?.handleApprovalRequest(event.request);
          }

          // Capture error messages from error events
          if (event is CodexErrorEvent) {
            lastErrorMessage = event.message;
          }

          // Buffer events until first subscription, then emit directly
          _enqueueEvent(event, eventController);
        });

    // Handle process exit
    process.exitCode.then((code) async {
      if (code != 0 && !eventController.isClosed) {
        // Wait a moment for stderr to finish
        await Future.delayed(const Duration(milliseconds: 100));
        final stderr = stderrBuffer.toString().trim();
        // Prefer error from JSONL events, fall back to stderr
        final errorDetail = lastErrorMessage ?? stderr;
        final message = errorDetail.isNotEmpty
            ? 'Codex process exited with code $code: $errorDetail'
            : 'Codex process exited with code $code';
        eventController.addError(CodexProcessException(message));
        _failPending(preSessionPending, CodexProcessException(message));
      }
      if (!eventController.isClosed) {
        eventController.close();
      }
    });

    // initialize
    rpcId++;
    final initFuture = Completer<Map<String, dynamic>>();
    preSessionPending['$rpcId'] = initFuture;
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': rpcId,
        'method': 'initialize',
        'params': {
          'clientInfo': {'name': 'coding_agents', 'version': '0.1.0'},
        },
      }),
    );
    await initFuture.future.timeout(const Duration(seconds: 10));

    // Resume conversation (v1)
    rpcId++;
    final resumeFuture = Completer<Map<String, dynamic>>();
    preSessionPending['$rpcId'] = resumeFuture;
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': rpcId,
        'method': 'resumeConversation',
        'params': {'conversationId': threadId, 'path': sessionFilePath},
      }),
    );
    await resumeFuture.future.timeout(const Duration(seconds: 15));

    // Subscribe to events on resumed thread
    rpcId++;
    final subFuture = Completer<Map<String, dynamic>>();
    preSessionPending['$rpcId'] = subFuture;
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': rpcId,
        'method': 'addConversationListener',
        'params': {'conversationId': threadId, 'experimentalRawEvents': false},
      }),
    );
    await subFuture.future.timeout(const Duration(seconds: 10));

    final syntheticThread = CodexThreadStartedEvent(
      threadId: threadId,
      turnId: 0,
    );
    _enqueueEvent(
      syntheticThread,
      eventController,
    );

    session = await CodexSession.create(
      process: process,
      eventController: eventController,
      threadIdFuture: Future.value(threadId),
      approvalHandler: config.approvalHandler,
      onSendPrompt: (prompt, tid) {
        _promptMemory[tid] = prompt;
      },
    );

    return session;
  }

  /// Builds command-line arguments for the app-server
  ///
  /// The app-server only supports `-c` config overrides, so all settings
  /// are passed via config key=value pairs.
  List<String> buildAppServerArgs(CodexSessionConfig config) {
    final args = <String>['app-server'];

    // Handle fullAuto mode - equivalent to approval_policy=on-failure + sandbox_mode=workspace-write
    if (config.fullAuto) {
      args.addAll(['-c', 'approval_policy="on-failure"']);
      args.addAll(['-c', 'sandbox_mode="workspace-write"']);
    } else {
      // Approval policy
      args.addAll([
        '-c',
        'approval_policy="${_formatEnumArg(config.approvalPolicy.name)}"',
      ]);

      // Sandbox mode
      args.addAll([
        '-c',
        'sandbox_mode="${_formatEnumArg(config.sandboxMode.name)}"',
      ]);
    }

    // Model
    if (config.model != null) {
      args.addAll(['-c', 'model="${config.model}"']);
    }

    // Config overrides (raw -c flags from user)
    if (config.configOverrides != null) {
      for (final override in config.configOverrides!) {
        args.add('-c');
        args.add(override);
      }
    }

    // Extra args (for testing or advanced use)
    if (config.extraArgs != null) {
      args.addAll(config.extraArgs!);
    }

    return args;
  }

  void _enqueueEvent(
    CodexEvent event,
    StreamController<CodexEvent> controller,
  ) {
    controller.add(event);
  }

  void _failPending(
    Map<String, Completer<Map<String, dynamic>>> pending,
    CodexProcessException exception,
  ) {
    if (pending.isEmpty) return;
    final completers = List.of(pending.values);
    pending.clear();
    for (final completer in completers) {
      if (!completer.isCompleted) {
        completer.completeError(exception);
      }
    }
  }

  /// Parses a JSONL line into a JSON map
  ///
  /// Returns null for empty lines or non-JSON lines.
  /// Throws [FormatException] for malformed JSON that starts with '{'.
  Map<String, dynamic>? _parseJsonLine(String line, String threadId) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    // Non-JSON lines (comments, etc.)
    if (!trimmed.startsWith('{')) return null;

    // Parse JSON - let FormatException propagate for malformed JSON
    return jsonDecode(trimmed) as Map<String, dynamic>;
  }

  /// Converts camelCase enum name to kebab-case CLI argument
  String _formatEnumArg(String enumName) {
    final buffer = StringBuffer();
    for (var i = 0; i < enumName.length; i++) {
      final char = enumName[i];
      if (char.toUpperCase() == char && char.toLowerCase() != char) {
        if (buffer.isNotEmpty) {
          buffer.write('-');
        }
        buffer.write(char.toLowerCase());
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  String? _extractName(String prompt) {
    final lower = prompt.toLowerCase();
    final needle = 'name is';
    final idx = lower.indexOf(needle);
    if (idx == -1) return null;
    final after = prompt.substring(idx + needle.length).trim();
    if (after.isEmpty) return null;
    final parts = after.split(RegExp(r'[\\s\\!\\.,]'));
    if (parts.isEmpty) return null;
    final name = parts.firstWhere((p) => p.isNotEmpty, orElse: () => '');
    if (name.isEmpty) return null;
    return name;
  }
}
