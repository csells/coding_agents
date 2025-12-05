/// Simple interactive CLI for Gemini
///
/// Usage:
///   dart run example/simple_cli/gemini_cli.dart [options]
///
/// Options:
///   -d, --project-directory  Working directory (default: current directory)
///   -p, --prompt             Execute a single prompt and exit
///   -s, --list-sessions      List available sessions
///   -r, --resume-session     Resume a session by ID
///   -y, --yolo               Skip permission prompts
///
/// Examples:
///   dart run example/simple_cli/gemini_cli.dart
///   dart run example/simple_cli/gemini_cli.dart -p "What is 2+2?"
///   dart run example/simple_cli/gemini_cli.dart -s
///   dart run example/simple_cli/gemini_cli.dart -r abc123-def456
///   dart run example/simple_cli/gemini_cli.dart -r abc123 -p "Continue"
library;

import 'dart:io';

import 'package:coding_agents/coding_agents.dart';

Future<void> main(List<String> args) async {
  final parsed = _parseArgs(args);
  final projectDir = parsed.projectDirectory ?? Directory.current.path;
  final client = GeminiCliAdapter(cwd: projectDir);

  if (parsed.listSessions) {
    await _listSessions(client);
    return;
  }

  if (parsed.resumeSession != null) {
    if (parsed.prompt != null) {
      // One-shot with resumed session
      await _oneShot(client, parsed.prompt!, parsed.yolo,
          sessionId: parsed.resumeSession);
    } else {
      // REPL with resumed session
      await _showHistory(client, parsed.resumeSession!);
      await _repl(client, parsed.yolo, sessionId: parsed.resumeSession);
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

Future<void> _listSessions(GeminiCliAdapter client) async {
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
    final history = await client.getSessionHistory(session.sessionId);
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

Future<void> _showHistory(GeminiCliAdapter client, String sessionId) async {
  print('Loading session history...');
  print('');

  final history = await client.getSessionHistory(sessionId);

  for (final event in history) {
    switch (event) {
      case GeminiMessageEvent():
        if (event.role == 'user') {
          print('You: ${event.content}');
        } else if (event.role == 'assistant') {
          print('Gemini: ${event.content}');
        }
      case GeminiToolUseEvent():
        print('Tool: ${event.toolUse.toolName}(${_formatParams(event.toolUse.parameters)})');
      case GeminiToolResultEvent():
        print('Tool Result [${event.toolResult.status}]: ${_truncate(event.toolResult.output ?? '', 200)}');
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
  bool yolo, {
  String? sessionId,
}) async {
  final config = GeminiSessionConfig(
    approvalMode: yolo ? GeminiApprovalMode.yolo : GeminiApprovalMode.defaultMode,
  );

  final session = sessionId != null
      ? await client.resumeSession(sessionId, prompt, config)
      : await client.createSession(prompt, config);

  await for (final event in session.events) {
    switch (event) {
      case GeminiMessageEvent():
        if (event.role == 'assistant') {
          stdout.write(event.content);
        }
      case GeminiToolUseEvent():
        print('\n[Tool: ${event.toolUse.toolName}]');
      case GeminiResultEvent():
        print('');
        break;
      case GeminiErrorEvent():
        print('Error: ${event.message}');
        break;
      default:
        break;
    }
  }
}

Future<void> _repl(
  GeminiCliAdapter client,
  bool yolo, {
  String? sessionId,
}) async {
  print('Gemini CLI (type "exit" to quit)');
  print('');

  String? currentSessionId = sessionId;

  while (true) {
    stdout.write('You: ');
    final input = stdin.readLineSync();

    if (input == null || input.toLowerCase() == 'exit') {
      print('Goodbye!');
      break;
    }

    if (input.trim().isEmpty) continue;

    final config = GeminiSessionConfig(
      approvalMode: yolo ? GeminiApprovalMode.yolo : GeminiApprovalMode.defaultMode,
    );

    final session = currentSessionId != null
        ? await client.resumeSession(currentSessionId, input, config)
        : await client.createSession(input, config);

    currentSessionId = session.sessionId;

    stdout.write('Gemini: ');
    await for (final event in session.events) {
      switch (event) {
        case GeminiMessageEvent():
          if (event.role == 'assistant') {
            stdout.write(event.content);
          }
        case GeminiToolUseEvent():
          print('\n[Tool: ${event.toolUse.toolName}]');
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
  final entries = params.entries.take(3).map((e) => '${e.key}: ${_truncate(e.value.toString(), 30)}');
  return entries.join(', ');
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
