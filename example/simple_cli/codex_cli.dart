/// Simple interactive CLI for Codex
///
/// Usage:
///   dart run example/simple_cli/codex_cli.dart [options]
///
/// Options:
///   -d, --project-directory  Working directory (default: current directory)
///   -p, --prompt             Execute a single prompt and exit
///   -s, --list-sessions      List available sessions
///   -r, --resume-session     Resume a session by ID
///   -y, --yolo               Skip permission prompts (full-auto mode)
///
/// Examples:
///   dart run example/simple_cli/codex_cli.dart
///   dart run example/simple_cli/codex_cli.dart -p "What is 2+2?"
///   dart run example/simple_cli/codex_cli.dart -s
///   dart run example/simple_cli/codex_cli.dart -r thread_abc123
///   dart run example/simple_cli/codex_cli.dart -r thread_abc123 -p "Continue"
library;

import 'dart:io';

import 'package:coding_agents/coding_agents.dart';

Future<void> main(List<String> args) async {
  final parsed = _parseArgs(args);
  final projectDir = parsed.projectDirectory ?? Directory.current.path;
  final client = CodexCliAdapter(cwd: projectDir);

  if (parsed.listSessions) {
    await _listSessions(client);
    return;
  }

  if (parsed.resumeSession != null) {
    if (parsed.prompt != null) {
      // One-shot with resumed session
      await _oneShot(client, parsed.prompt!, parsed.yolo,
          threadId: parsed.resumeSession);
    } else {
      // REPL with resumed session
      await _showHistory(client, parsed.resumeSession!);
      await _repl(client, parsed.yolo, threadId: parsed.resumeSession);
    }
    return;
  }

  if (parsed.prompt != null) {
    // One-shot mode
    await _oneShot(client, parsed.prompt!, parsed.yolo);
    return;
  }

  // Interactive REPL mode
  await _repl(client, parsed.yolo);
}

Future<void> _listSessions(CodexCliAdapter client) async {
  final sessions = await client.listSessions();

  if (sessions.isEmpty) {
    print('No sessions found.');
    return;
  }

  print('Sessions (${sessions.length}):');
  print('');

  for (final session in sessions) {
    // Get the first prompt from history
    String firstPrompt = '(no prompt)';
    final history = await client.getSessionHistory(session.threadId);
    for (final event in history) {
      if (event is CodexItemCompletedEvent) {
        final item = event.item;
        if (item is CodexAgentMessageItem) {
          // The first user message is typically from the prompt
          // But Codex might not store user messages as events
          // Try to get the agent's first response instead
          firstPrompt = item.text;
          if (firstPrompt.length > 60) {
            firstPrompt = '${firstPrompt.substring(0, 60)}...';
          }
          break;
        }
      }
    }

    print('  ${session.threadId}');
    print('    Prompt: $firstPrompt');
    print('    Updated: ${session.lastUpdated}');
    print('');
  }
}

Future<void> _showHistory(CodexCliAdapter client, String threadId) async {
  print('Loading session history...');
  print('');

  final history = await client.getSessionHistory(threadId);

  for (final event in history) {
    switch (event) {
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
  bool yolo, {
  String? threadId,
}) async {
  final config = CodexSessionConfig(
    fullAuto: yolo,
  );

  final session = threadId != null
      ? await client.resumeSession(threadId, prompt, config)
      : await client.createSession(prompt, config);

  await for (final event in session.events) {
    switch (event) {
      case CodexItemCompletedEvent():
        final item = event.item;
        if (item is CodexAgentMessageItem) {
          stdout.write(item.text);
        } else if (item is CodexToolCallItem) {
          print('\n[Tool: ${item.name}]');
        }
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

Future<void> _repl(
  CodexCliAdapter client,
  bool yolo, {
  String? threadId,
}) async {
  print('Codex CLI (type "exit" to quit)');
  print('');

  String? currentThreadId = threadId;

  while (true) {
    stdout.write('You: ');
    final input = stdin.readLineSync();

    if (input == null || input.toLowerCase() == 'exit') {
      print('Goodbye!');
      break;
    }

    if (input.trim().isEmpty) continue;

    final config = CodexSessionConfig(
      fullAuto: yolo,
    );

    final session = currentThreadId != null
        ? await client.resumeSession(currentThreadId, input, config)
        : await client.createSession(input, config);

    currentThreadId = session.threadId;

    stdout.write('Codex: ');
    await for (final event in session.events) {
      switch (event) {
        case CodexItemCompletedEvent():
          final item = event.item;
          if (item is CodexAgentMessageItem) {
            stdout.write(item.text);
          } else if (item is CodexToolCallItem) {
            print('\n[Tool: ${item.name}]');
          }
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

  _ParsedArgs({
    this.projectDirectory,
    this.prompt,
    this.listSessions = false,
    this.resumeSession,
    this.yolo = false,
  });
}

_ParsedArgs _parseArgs(List<String> args) {
  String? projectDirectory;
  String? prompt;
  bool listSessions = false;
  String? resumeSession;
  bool yolo = false;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];

    switch (arg) {
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
      case '-s':
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
  );
}
