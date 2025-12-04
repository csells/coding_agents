/// Example demonstrating the Gemini CLI adapter capabilities.
///
/// This example shows:
/// - Creating a session with sandbox mode
/// - Streaming events (init, message, tool_use, result)
/// - Multi-turn conversations via resumeSession
/// - Configuration options (model, approval mode, sandbox)
///
/// Prerequisites:
/// - Gemini CLI must be installed and authenticated
/// - Run from a directory where Gemini has permission to operate
library;

import 'dart:io';

import 'package:coding_agents/coding_agents.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  // Use tmp/ folder to avoid polluting the project
  final workDir = p.join(Directory.current.path, 'tmp');
  Directory(workDir).createSync(recursive: true);

  final client = GeminiClient(cwd: workDir);

  // Example 1: Simple single-turn session with sandbox
  print('=== Example 1: Simple Session (Sandbox Mode) ===');
  await simpleSingleTurn(client);

  // Example 2: Multi-turn conversation
  print('\n=== Example 2: Multi-Turn Conversation ===');
  await multiTurnConversation(client);

  // Example 3: Custom configuration
  print('\n=== Example 3: Custom Configuration ===');
  await customConfiguration(client);
}

/// Simple single-turn session with sandbox mode
Future<void> simpleSingleTurn(GeminiClient client) async {
  final config = GeminiSessionConfig(
    // yolo skips all approval prompts
    approvalMode: GeminiApprovalMode.yolo,
    // sandbox prevents file modifications
    sandbox: true,
  );

  final session = await client.createSession(
    'What is the square root of 144? Reply with just the number.',
    config,
  );

  print('Session ID: ${session.sessionId}');

  // Process events from the session
  await for (final event in session.events) {
    switch (event) {
      case GeminiInitEvent():
        print('Session initialized: ${event.sessionId}');
        print('Model: ${event.model}');
      case GeminiMessageEvent():
        if (event.role == 'assistant') {
          print('Assistant: ${event.content}');
        }
      case GeminiToolUseEvent():
        print('Tool call: ${event.toolUse.toolName}');
        print('  Parameters: ${event.toolUse.parameters}');
      case GeminiToolResultEvent():
        print('Tool result: ${event.toolResult.status}');
      case GeminiResultEvent():
        print('Result: ${event.status}');
        if (event.stats != null) {
          print(
            '  Tokens: ${event.stats!.inputTokens} in / '
            '${event.stats!.outputTokens} out',
          );
        }
      default:
        // Handle other event types
        break;
    }
  }
}

/// Multi-turn conversation using resumeSession
Future<void> multiTurnConversation(GeminiClient client) async {
  final config = GeminiSessionConfig(
    approvalMode: GeminiApprovalMode.yolo,
    sandbox: true,
  );

  // First turn: Establish context
  print('Turn 1: Establishing context...');
  final session1 = await client.createSession(
    'Remember this number: 42. Just say "OK, I will remember 42".',
    config,
  );

  final sessionId = session1.sessionId;
  print('Session ID: $sessionId');

  await for (final event in session1.events) {
    if (event is GeminiMessageEvent && event.role == 'assistant') {
      print('Assistant: ${event.content}');
    }
    if (event is GeminiResultEvent) break;
  }

  // Second turn: Recall context using the actual session ID
  print('\nTurn 2: Recalling context...');
  final session2 = await client.resumeSession(
    sessionId, // Uses actual UUID, not "latest"
    'What number did I ask you to remember?',
    config,
  );

  await for (final event in session2.events) {
    if (event is GeminiMessageEvent && event.role == 'assistant') {
      print('Assistant: ${event.content}');
    }
    if (event is GeminiResultEvent) {
      print('Multi-turn conversation completed.');
      break;
    }
  }
}

/// Example with custom configuration options
Future<void> customConfiguration(GeminiClient client) async {
  final config = GeminiSessionConfig(
    // autoEdit mode auto-approves file edits
    approvalMode: GeminiApprovalMode.autoEdit,
    // Specify a particular model
    model: 'gemini-2.0-flash-exp',
    // Enable debug output
    debug: false,
    // Custom sandbox image (when sandbox is enabled)
    sandbox: true,
    sandboxImage: null, // Use default sandbox image
  );

  final session = await client.createSession(
    'What is 7 * 8? Reply with just the number.',
    config,
  );

  print('Session ID: ${session.sessionId}');

  await for (final event in session.events) {
    if (event is GeminiInitEvent) {
      print('Model: ${event.model}');
    }
    if (event is GeminiMessageEvent && event.role == 'assistant') {
      print('Assistant: ${event.content}');
    }
    if (event is GeminiResultEvent) {
      print('Status: ${event.status}');
      break;
    }
  }
}

/// Example of session cancellation (not run by default)
Future<void> cancelSessionExample(GeminiClient client) async {
  final config = GeminiSessionConfig(
    approvalMode: GeminiApprovalMode.yolo,
    sandbox: true,
  );

  final session = await client.createSession(
    'Count from 1 to 100, one number per line.',
    config,
  );

  var messageCount = 0;
  await for (final event in session.events) {
    if (event is GeminiMessageEvent) {
      messageCount++;
      if (messageCount >= 3) {
        print('Cancelling session after $messageCount messages...');
        await session.cancel();
        break;
      }
    }
  }

  print('Session cancelled.');
}
