/// Simple interactive CLI for Codex
library;

import 'dart:io';

import 'package:coding_agents/coding_agents.dart';

void _printHelp() {
  print('''
Codex CLI - Simple interactive CLI for Codex

Usage:
  dart run codex_cli.dart [options]

Options:
  -h, --help               Show this help message
  -d, --project-directory  Working directory (default: current directory)
  -p, --prompt             Execute a single prompt and exit
  -l, --list-sessions      List available sessions
  -r, --resume-session     Resume a session by ID
  -y, --yolo               Skip permission prompts (full-auto mode)

Examples:
  dart run codex_cli.dart
  dart run codex_cli.dart -p "What is 2+2?"
  dart run codex_cli.dart -l
  dart run codex_cli.dart -r thread_abc123
  dart run codex_cli.dart -r thread_abc123 -p "Continue"
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

Future<void> main(List<String> args) async {
  final parsed = _parseArgs(args);

  if (parsed.showHelp) {
    _printHelp();
    return;
  }

  final projectDir = parsed.projectDirectory ?? Directory.current.path;
  final client = CodexCliAdapter();

  if (parsed.listSessions) {
    await _listSessions(client, projectDir);
    return;
  }

  if (parsed.resumeSession != null) {
    if (parsed.prompt != null) {
      // One-shot with resumed session
      await _oneShot(
        client,
        parsed.prompt!,
        parsed.yolo,
        projectDir,
        threadId: parsed.resumeSession,
      );
    } else {
      // REPL with resumed session
      await _showHistory(client, parsed.resumeSession!, projectDir);
      await _repl(
        client,
        parsed.yolo,
        projectDir,
        threadId: parsed.resumeSession,
      );
    }
    return;
  }

  if (parsed.prompt != null) {
    // One-shot mode
    await _oneShot(client, parsed.prompt!, parsed.yolo, projectDir);
    return;
  }

  // Interactive REPL mode
  await _repl(client, parsed.yolo, projectDir);
}

Future<void> _listSessions(CodexCliAdapter client, String projectDir) async {
  final sessions = await client.listSessions(projectDirectory: projectDir);

  if (sessions.isEmpty) {
    print('No sessions found.');
    return;
  }

  print('Sessions (${sessions.length}):');
  print('');

  for (final session in sessions) {
    // Get the first prompt from history
    String firstPrompt = '(no prompt)';
    final history = await client.getSessionHistory(
      session.threadId,
      projectDirectory: projectDir,
    );
    for (final event in history) {
      if (event is CodexUserMessageEvent) {
        firstPrompt = event.message;
        if (firstPrompt.length > 60) {
          firstPrompt = '${firstPrompt.substring(0, 60)}...';
        }
        break;
      }
    }

    print('  ${session.threadId}');
    print('    Prompt: $firstPrompt');
    print('    Updated: ${session.lastUpdated}');
    print('');
  }
}

Future<void> _showHistory(
  CodexCliAdapter client,
  String threadId,
  String projectDir,
) async {
  print('Loading session history...');
  print('');

  final history = await client.getSessionHistory(
    threadId,
    projectDirectory: projectDir,
  );

  for (final event in history) {
    switch (event) {
      case CodexUserMessageEvent():
        print('You: ${event.message}');
      case CodexItemCompletedEvent():
        final item = event.item;
        switch (item) {
          case CodexAgentMessageItem():
            print('Codex: ${item.text}');
          case CodexToolCallItem():
            print('Tool: ${item.name}');
            if (item.output != null) {
              print('  Output: ${_truncate(item.output!, 200)}');
            }
          case CodexFileChangeItem():
            print('File: ${item.path}');
            if (item.diff != null) {
              print('  Diff: ${_truncate(item.diff!, 200)}');
            }
          case CodexReasoningItem():
            if (item.summary != null) {
              print('Thinking: ${_truncate(item.summary!, 100)}');
            }
          default:
            break;
        }
      case CodexTurnCompletedEvent():
        print('--- Turn complete ---');
      default:
        break;
    }
  }

  print('');
  print('=== Session resumed ===');
  print('');
}

Future<void> _oneShot(
  CodexCliAdapter client,
  String prompt,
  bool yolo,
  String projectDir, {
  String? threadId,
}) async {
  // Create config with approval handler for interactive mode
  final config = CodexSessionConfig(
    fullAuto: yolo,
    // When not in yolo mode, use an approval callback to prompt user
    approvalHandler: yolo ? null : _approvalHandler,
  );

  final session = threadId != null
      ? await client.resumeSession(
          threadId,
          prompt,
          config,
          projectDirectory: projectDir,
        )
      : await client.createSession(
          prompt,
          config,
          projectDirectory: projectDir,
        );

  await for (final event in session.events) {
    switch (event) {
      case CodexItemCompletedEvent():
        final item = event.item;
        if (item is CodexAgentMessageItem) {
          stdout.write(item.text);
        } else if (item is CodexToolCallItem) {
          print('\n[Tool: ${item.name}]');
        }
      case CodexApprovalRequiredEvent():
        // This will be handled by the approvalHandler callback
        print('\n[Approval request: ${event.request.description}]');
      case CodexTurnCompletedEvent():
        print('');
        break;
      case CodexErrorEvent():
        print('Error: ${event.message}');
        break;
      default:
        break;
    }
  }
}

/// Approval handler callback for interactive approval prompts
Future<CodexApprovalResponse> _approvalHandler(
  CodexApprovalRequest request,
) async {
  print('');
  print('=== Approval Required ===');
  print('Action: ${request.actionType}');
  print('Description: ${request.description}');
  if (request.command != null) {
    print('Command: ${request.command}');
  }
  if (request.filePath != null) {
    print('File: ${request.filePath}');
  }
  print('');
  stdout.write('Allow? [y/n/a(always)/d(never)]: ');

  final input = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';

  return switch (input) {
    'y' || 'yes' => CodexApprovalResponse(decision: CodexApprovalDecision.allow),
    'a' || 'always' => CodexApprovalResponse(
        decision: CodexApprovalDecision.allowAlways,
      ),
    'd' || 'never' => CodexApprovalResponse(
        decision: CodexApprovalDecision.denyAlways,
      ),
    _ => CodexApprovalResponse(decision: CodexApprovalDecision.deny),
  };
}

Future<void> _repl(
  CodexCliAdapter client,
  bool yolo,
  String projectDir, {
  String? threadId,
}) async {
  print('Codex CLI (app-server mode)');
  print('');
  _printReplHelp();

  String? currentThreadId = threadId;
  CodexSession? activeSession;

  while (true) {
    stdout.write('You: ');
    final input = stdin.readLineSync();

    if (input == null) {
      print('Goodbye!');
      await activeSession?.cancel();
      break;
    }

    final trimmed = input.trim().toLowerCase();
    if (trimmed == '/exit' || trimmed == '/quit') {
      print('Goodbye!');
      await activeSession?.cancel();
      break;
    }

    if (trimmed == '/help') {
      _printReplHelp();
      continue;
    }

    if (input.trim().isEmpty) continue;

    // Create config with approval handler for interactive mode
    final config = CodexSessionConfig(
      fullAuto: yolo,
      approvalHandler: yolo ? null : _approvalHandler,
    );

    // If we have an active session, use send() for multi-turn
    // Otherwise create a new session
    if (activeSession != null && currentThreadId != null) {
      await activeSession.send(input);
    } else {
      activeSession = currentThreadId != null
          ? await client.resumeSession(
              currentThreadId,
              input,
              config,
              projectDirectory: projectDir,
            )
          : await client.createSession(
              input,
              config,
              projectDirectory: projectDir,
            );

      currentThreadId = activeSession.threadId;
    }

    stdout.write('Codex: ');
    await for (final event in activeSession!.events) {
      switch (event) {
        case CodexItemCompletedEvent():
          final item = event.item;
          if (item is CodexAgentMessageItem) {
            stdout.write(item.text);
          } else if (item is CodexToolCallItem) {
            print('\n[Tool: ${item.name}]');
          }
        case CodexApprovalRequiredEvent():
          print('\n[Approval request: ${event.request.description}]');
        case CodexTurnCompletedEvent():
          print('');
          print('');
          break;
        case CodexErrorEvent():
          print('\nError: ${event.message}');
          break;
        default:
          break;
      }
    }
  }
}

String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}...';
}

class _ParsedArgs {
  final String? projectDirectory;
  final String? prompt;
  final bool listSessions;
  final String? resumeSession;
  final bool yolo;
  final bool showHelp;

  _ParsedArgs({
    this.projectDirectory,
    this.prompt,
    this.listSessions = false,
    this.resumeSession,
    this.yolo = false,
    this.showHelp = false,
  });
}

_ParsedArgs _parseArgs(List<String> args) {
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
    projectDirectory: projectDirectory,
    prompt: prompt,
    listSessions: listSessions,
    resumeSession: resumeSession,
    yolo: yolo,
    showHelp: showHelp,
  );
}
