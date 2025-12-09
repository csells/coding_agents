/// Simple interactive CLI for Gemini
library;

import 'dart:io';

import 'package:coding_agents/coding_agents.dart';

void _printHelp() {
  print('''
Gemini CLI - Simple interactive CLI for Gemini

Usage:
  dart run gemini_cli.dart [options]

Options:
  -h, --help               Show this help message
  -d, --project-directory  Working directory (default: current directory)
  -p, --prompt             Execute a single prompt and exit
  -l, --list-sessions      List available sessions
  -r, --resume-session     Resume a session by ID
  -y, --yolo               Skip permission prompts

Examples:
  dart run gemini_cli.dart
  dart run gemini_cli.dart -p "What is 2+2?"
  dart run gemini_cli.dart -l
  dart run gemini_cli.dart -r abc123-def456
  dart run gemini_cli.dart -r abc123 -p "Continue"
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
  final client = GeminiCliAdapter();

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
        sessionId: parsed.resumeSession,
      );
    } else {
      // REPL with resumed session
      await _showHistory(client, parsed.resumeSession!, projectDir);
      await _repl(
        client,
        parsed.yolo,
        projectDir,
        sessionId: parsed.resumeSession,
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

Future<void> _listSessions(GeminiCliAdapter client, String projectDir) async {
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
      session.sessionId,
      projectDirectory: projectDir,
    );
    for (final event in history) {
      if (event is GeminiMessageEvent && event.role == 'user') {
        firstPrompt = event.content;
        if (firstPrompt.length > 60) {
          firstPrompt = '${firstPrompt.substring(0, 60)}...';
        }
        break;
      }
    }

    print('  ${session.sessionId}');
    print('    Prompt: $firstPrompt');
    print('    Updated: ${session.lastUpdated}');
    print('');
  }
}

Future<void> _showHistory(
  GeminiCliAdapter client,
  String sessionId,
  String projectDir,
) async {
  print('Loading session history...');
  print('');

  final history = await client.getSessionHistory(
    sessionId,
    projectDirectory: projectDir,
  );

  for (final event in history) {
    switch (event) {
      case GeminiMessageEvent():
        if (event.role == 'user') {
          print('You: ${event.content}');
        } else if (event.role == 'assistant') {
          print('Gemini: ${event.content}');
        }
      case GeminiToolUseEvent():
        print(
          'Tool: ${event.toolUse.toolName}(${_formatParams(event.toolUse.parameters)})',
        );
      case GeminiToolResultEvent():
        print(
          'Tool Result [${event.toolResult.status}]: ${_truncate(event.toolResult.output ?? '', 200)}',
        );
      case GeminiResultEvent():
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
  GeminiCliAdapter client,
  String prompt,
  bool yolo,
  String projectDir, {
  String? sessionId,
}) async {
  final config = GeminiSessionConfig(
    approvalMode: yolo
        ? GeminiApprovalMode.yolo
        : GeminiApprovalMode.defaultMode,
  );

  final session = sessionId != null
      ? client.resumeSession(
          sessionId,
          config,
          projectDirectory: projectDir,
        )
      : client.createSession(
          config,
          projectDirectory: projectDir,
        );

  await session.send(prompt);

  await for (final event in session.events) {
    switch (event) {
      case GeminiMessageEvent():
        if (event.role == 'assistant') {
          stdout.write(event.content);
        }
      case GeminiToolUseEvent():
        print('\n[Tool: ${event.toolUse.toolName}(${_formatParams(event.toolUse.parameters)})]');
      case GeminiResultEvent():
        print('');
        await session.cancel();
        return;
      case GeminiErrorEvent():
        print('Error: ${event.message}');
        await session.cancel();
        return;
      default:
        break;
    }
  }
}

Future<void> _repl(
  GeminiCliAdapter client,
  bool yolo,
  String projectDir, {
  String? sessionId,
}) async {
  print('Gemini CLI');
  print('');
  _printReplHelp();

  String? currentSessionId = sessionId;

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

    final config = GeminiSessionConfig(
      approvalMode: yolo
          ? GeminiApprovalMode.yolo
          : GeminiApprovalMode.defaultMode,
    );

    final session = currentSessionId != null
        ? client.resumeSession(
            currentSessionId,
            config,
            projectDirectory: projectDir,
          )
        : client.createSession(
            config,
            projectDirectory: projectDir,
          );

    currentSessionId = session.sessionId;

    await session.send(input);

    stdout.write('Gemini: ');
    await for (final event in session.events) {
      switch (event) {
        case GeminiMessageEvent():
          if (event.role == 'assistant') {
            stdout.write(event.content);
          }
        case GeminiToolUseEvent():
          print('\n[Tool: ${event.toolUse.toolName}(${_formatParams(event.toolUse.parameters)})]');
        case GeminiResultEvent():
          print('');
          print('');
          break;
        case GeminiErrorEvent():
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

String _formatParams(Map<String, dynamic> params) {
  final entries = params.entries
      .take(3)
      .map((e) => '${e.key}: ${_truncate(e.value.toString(), 30)}');
  return entries.join(', ');
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
