/// Unified interactive CLI for coding agents
///
/// Supports Claude, Codex, and Gemini via the --agent flag.
library;

import 'dart:async';
import 'dart:io';

import 'package:coding_agents/src/coding_agent/coding_agents.dart';

void _printHelp() {
  print('''
Coding Agent CLI - Unified CLI for Claude, Codex, and Gemini

Usage:
  dart run example/coding_cli.dart [options]

Options:
  -h, --help               Show this help message
  -a, --agent <name>       Agent to use: claude, codex, gemini (default: claude)
  -d, --project-directory  Working directory (default: current directory)
  -p, --prompt             Execute a single prompt and exit
  -l, --list-sessions      List available sessions
  -r, --resume-session     Resume a session by ID
  -y, --yolo               Skip permission/approval prompts

Examples:
  dart run example/coding_cli.dart
  dart run example/coding_cli.dart -a gemini
  dart run example/coding_cli.dart -a codex -p "What is 2+2?"
  dart run example/coding_cli.dart -l
  dart run example/coding_cli.dart -r abc123
  dart run example/coding_cli.dart -r abc123 -p "Continue from here"
''');
}

void _printReplHelp() {
  print('''
Available commands:
  /help   Show this help message
  /exit   Exit the REPL
  /quit   Exit the REPL
''');
}

/// Approval handler callback for interactive tool approval prompts
Future<ToolApprovalResponse> _approvalHandler(ToolApprovalRequest request) async {
  print('');
  print('=== Approval Required ===');
  print('Tool: ${request.toolName}');
  print('Description: ${request.description}');
  if (request.command != null) {
    print('Command: ${request.command}');
  }
  if (request.filePath != null) {
    print('File: ${request.filePath}');
  }
  if (request.input != null) {
    print('Input: ${_formatInput(request.input!)}');
  }
  stdout.write('Yes/No/Always/neVer? [N]: ');

  final input = stdin.readLineSync()?.trim().toLowerCase() ?? '';

  return switch (input) {
    'y' || 'yes' => ToolApprovalResponse(decision: ToolApprovalDecision.allow),
    'a' || 'always' => ToolApprovalResponse(decision: ToolApprovalDecision.allowAlways),
    'v' || 'never' => ToolApprovalResponse(decision: ToolApprovalDecision.denyAlways),
    _ => ToolApprovalResponse(decision: ToolApprovalDecision.deny),
  };
}

Future<void> main(List<String> args) async {
  final parsed = _parseArgs(args);

  if (parsed.showHelp) {
    _printHelp();
    return;
  }

  final projectDir = parsed.projectDirectory ?? Directory.current.path;
  final agent = _createAgent(parsed.agent, parsed.yolo);
  final agentName = _agentDisplayName(parsed.agent);

  if (parsed.listSessions) {
    await _listSessions(agent, agentName, projectDir);
    return;
  }

  if (parsed.resumeSession != null) {
    if (parsed.prompt != null) {
      await _oneShot(
        agent,
        agentName,
        parsed.prompt!,
        projectDir,
        yolo: parsed.yolo,
        sessionId: parsed.resumeSession,
      );
    } else {
      await _showHistory(agent, agentName, parsed.resumeSession!, projectDir);
      await _repl(
        agent,
        agentName,
        projectDir,
        yolo: parsed.yolo,
        sessionId: parsed.resumeSession,
      );
    }
    return;
  }

  if (parsed.prompt != null) {
    await _oneShot(
      agent,
      agentName,
      parsed.prompt!,
      projectDir,
      yolo: parsed.yolo,
    );
    return;
  }

  await _repl(agent, agentName, projectDir, yolo: parsed.yolo);
}

CodingAgent _createAgent(String agentType, bool yolo) {
  switch (agentType) {
    case 'codex':
      // Note: fullAuto and dangerouslyBypassAll are mutually exclusive in Codex
      return CodexCodingAgent(
        fullAuto: yolo,
      );
    case 'gemini':
      return GeminiCodingAgent(
        approvalMode: yolo ? GeminiApprovalMode.yolo : GeminiApprovalMode.defaultMode,
      );
    case 'claude':
    default:
      return ClaudeCodingAgent(
        permissionMode: yolo
            ? ClaudePermissionMode.bypassPermissions
            : ClaudePermissionMode.defaultMode,
      );
  }
}

String _agentDisplayName(String agentType) {
  switch (agentType) {
    case 'codex':
      return 'Codex';
    case 'gemini':
      return 'Gemini';
    case 'claude':
    default:
      return 'Claude';
  }
}

Future<void> _listSessions(
  CodingAgent agent,
  String agentName,
  String projectDir,
) async {
  final sessions = await agent.listSessions(projectDirectory: projectDir);

  if (sessions.isEmpty) {
    print('No $agentName sessions found.');
    return;
  }

  print('$agentName Sessions (${sessions.length}):');
  print('');

  for (final session in sessions) {
    print('  ${session.sessionId}');
    if (session.gitBranch != null) {
      print('    Branch: ${session.gitBranch}');
    }
    print('    Updated: ${session.lastUpdatedAt}');
    print('');
  }
}

Future<void> _showHistory(
  CodingAgent agent,
  String agentName,
  String sessionId,
  String projectDir,
) async {
  print('Loading session history...');
  print('');

  final session = await agent.resumeSession(
    sessionId,
    projectDirectory: projectDir,
  );
  final history = await session.getHistory();

  for (final event in history) {
    switch (event) {
      case CodingAgentTextEvent():
        print('$agentName: ${event.text}');
      case CodingAgentThinkingEvent():
        print('Thinking: ${_truncate(event.thinking, 100)}');
      case CodingAgentToolUseEvent():
        print('Tool: ${event.toolName}(${_formatInput(event.input)})');
      case CodingAgentToolResultEvent():
        final status = event.isError ? 'Error' : 'Result';
        print('Tool $status: ${_truncate(event.output ?? '', 200)}');
      case CodingAgentTurnEndEvent():
        print('--- Turn ${event.turnId + 1} complete ---');
      default:
        break;
    }
  }

  await session.close();

  print('');
  print('=== Session resumed ===');
  print('');
}

Future<void> _oneShot(
  CodingAgent agent,
  String agentName,
  String prompt,
  String projectDir, {
  required bool yolo,
  String? sessionId,
}) async {
  final handler = yolo ? null : _approvalHandler;
  final session = sessionId != null
      ? await agent.resumeSession(
          sessionId,
          projectDirectory: projectDir,
          approvalHandler: handler,
        )
      : await agent.createSession(
          projectDirectory: projectDir,
          approvalHandler: handler,
        );

  // Subscribe to events before sending message
  final turnCompleted = Completer<void>();
  var sawPartialText = false;
  final eventSubscription = session.events.listen(
    (event) {
      switch (event) {
        case CodingAgentTextEvent():
          if (event.isPartial) {
            sawPartialText = true;
            stdout.write(event.text);
          } else if (!sawPartialText) {
            stdout.write(event.text);
          }
        case CodingAgentThinkingEvent():
          // Optionally show thinking
          break;
        case CodingAgentToolUseEvent():
          print('\n[Tool: ${event.toolName}(${_formatInput(event.input)})]');
        case CodingAgentToolResultEvent():
          // Tool results are internal
          break;
        case CodingAgentTurnEndEvent():
          print('');
          sawPartialText = false;
          if (!turnCompleted.isCompleted) turnCompleted.complete();
        case CodingAgentErrorEvent():
          print('\nError: ${event.message}');
          if (!turnCompleted.isCompleted) turnCompleted.completeError(Exception(event.message));
        default:
          break;
      }
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!turnCompleted.isCompleted) {
        turnCompleted.completeError(error, stackTrace);
      }
    },
  );

  // Send the message
  await session.sendMessage(prompt);

  // Wait for the current turn to finish (a turn end or error event)
  await turnCompleted.future;
  await eventSubscription.cancel();
  await session.close();
}

Future<void> _repl(
  CodingAgent agent,
  String agentName,
  String projectDir, {
  required bool yolo,
  String? sessionId,
}) async {
  print('$agentName CLI');
  print('');
  _printReplHelp();

  final handler = yolo ? null : _approvalHandler;
  CodingAgentSession? session;

  // Create or resume session
  if (sessionId != null) {
    session = await agent.resumeSession(
      sessionId,
      projectDirectory: projectDir,
      approvalHandler: handler,
    );
  } else {
    session = await agent.createSession(
      projectDirectory: projectDir,
      approvalHandler: handler,
    );
  }

  while (true) {
    stdout.write('You: ');
    final input = stdin.readLineSync();

    if (input == null) {
      print('Goodbye!');
      break;
    }

    final trimmed = input.trim().toLowerCase();
    if (trimmed == '/exit' || trimmed == '/quit') {
      print('Goodbye!');
      break;
    }

    if (trimmed == '/help') {
      _printReplHelp();
      continue;
    }

    if (input.trim().isEmpty) continue;

    stdout.write('$agentName: ');

    // Send message and process events
    await session.sendMessage(input);

    // Process events until turn ends
    var sawPartialText = false;
    await for (final event in session.events) {
      switch (event) {
        case CodingAgentTextEvent():
          if (event.isPartial) {
            sawPartialText = true;
            stdout.write(event.text);
          } else if (!sawPartialText) {
            stdout.write(event.text);
          }
        case CodingAgentThinkingEvent():
          // Optionally show thinking
          break;
        case CodingAgentToolUseEvent():
          print('\n[Tool: ${event.toolName}(${_formatInput(event.input)})]');
        case CodingAgentToolResultEvent():
          // Tool results are internal
          break;
        case CodingAgentTurnEndEvent():
          print('');
          print('');
          break;
        case CodingAgentErrorEvent():
          print('\nError: ${event.message}');
        default:
          break;
      }

      // Break after turn ends
      if (event is CodingAgentTurnEndEvent) break;
    }
  }

  await session.close();
}

String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}...';
}

String _formatInput(Map<String, dynamic> input) {
  final entries = input.entries
      .take(3)
      .map((e) => '${e.key}: ${_truncate(e.value.toString(), 30)}');
  return entries.join(', ');
}

class _ParsedArgs {
  final String agent;
  final String? projectDirectory;
  final String? prompt;
  final bool listSessions;
  final String? resumeSession;
  final bool yolo;
  final bool showHelp;

  _ParsedArgs({
    this.agent = 'claude',
    this.projectDirectory,
    this.prompt,
    this.listSessions = false,
    this.resumeSession,
    this.yolo = false,
    this.showHelp = false,
  });
}

_ParsedArgs _parseArgs(List<String> args) {
  String agent = 'claude';
  String? projectDirectory;
  String? prompt;
  bool listSessions = false;
  String? resumeSession;
  bool yolo = false;
  bool showHelp = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];

    switch (arg) {
      case '-h':
      case '--help':
        showHelp = true;
      case '-a':
      case '--agent':
        if (i + 1 < args.length) {
          final value = args[++i].toLowerCase();
          if (value == 'claude' || value == 'codex' || value == 'gemini') {
            agent = value;
          } else {
            print('Unknown agent: $value (using claude)');
          }
        }
      case '-d':
      case '--project-directory':
        if (i + 1 < args.length) {
          projectDirectory = args[++i];
        }
      case '-p':
      case '--prompt':
        if (i + 1 < args.length) {
          prompt = args[++i];
        }
      case '-l':
      case '--list-sessions':
        listSessions = true;
      case '-r':
      case '--resume-session':
        if (i + 1 < args.length) {
          resumeSession = args[++i];
        }
      case '-y':
      case '--yolo':
        yolo = true;
    }
  }

  return _ParsedArgs(
    agent: agent,
    projectDirectory: projectDirectory,
    prompt: prompt,
    listSessions: listSessions,
    resumeSession: resumeSession,
    yolo: yolo,
    showHelp: showHelp,
  );
}
