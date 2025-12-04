/// Example demonstrating the Claude Code CLI adapter capabilities.
///
/// This example shows:
/// - Creating a session with configuration options
/// - Streaming events from the session
/// - Multi-turn conversations via resumeSession
/// - Listing existing sessions
/// - Cancelling a session
///
/// Prerequisites:
/// - Claude Code CLI must be installed and authenticated
/// - Run from a directory where Claude has permission to operate
library;

import 'dart:io';

import 'package:coding_agents/coding_agents.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  // Use tmp/ folder to avoid polluting the project
  final workDir = p.join(Directory.current.path, 'tmp');
  Directory(workDir).createSync(recursive: true);

  final client = ClaudeClient(cwd: workDir);

  // Example 1: Simple single-turn session
  print('=== Example 1: Simple Session ===');
  await simpleSingleTurn(client);

  // Example 2: Multi-turn conversation
  print('\n=== Example 2: Multi-Turn Conversation ===');
  await multiTurnConversation(client);

  // Example 3: List existing sessions
  print('\n=== Example 3: List Sessions ===');
  await listExistingSessions(client);
}

/// Simple single-turn session with basic configuration
Future<void> simpleSingleTurn(ClaudeClient client) async {
  final config = ClaudeSessionConfig(
    // Skip permission prompts for automation
    permissionMode: ClaudePermissionMode.bypassPermissions,
    // Limit to single turn
    maxTurns: 1,
  );

  final session = await client.createSession(
    'What is 2 + 2? Reply with just the number.',
    config,
  );

  print('Session ID: ${session.sessionId}');

  // Process events from the session
  await for (final event in session.events) {
    if (event is ClaudeSystemEvent) {
      print('System [${event.subtype}]');
    } else if (event is ClaudeAssistantEvent) {
      // Collect text from content blocks
      for (final block in event.content) {
        if (block is ClaudeTextBlock) {
          print('Assistant: ${block.text}');
        }
      }
    } else if (event is ClaudeResultEvent) {
      print('Result: ${event.subtype}');
      if (event.usage != null) {
        print(
          '  Tokens: ${event.usage!.inputTokens} in / '
          '${event.usage!.outputTokens} out',
        );
      }
      break;
    }
  }
}

/// Multi-turn conversation using resumeSession
Future<void> multiTurnConversation(ClaudeClient client) async {
  final config = ClaudeSessionConfig(
    permissionMode: ClaudePermissionMode.bypassPermissions,
    maxTurns: 1,
  );

  // First turn: Establish context
  print('Turn 1: Establishing context...');
  final session1 = await client.createSession(
    'Remember this code: XYZ123. Just say "OK, I will remember XYZ123".',
    config,
  );

  final sessionId = session1.sessionId;
  print('Session ID: $sessionId');

  await for (final event in session1.events) {
    if (event is ClaudeAssistantEvent) {
      for (final block in event.content) {
        if (block is ClaudeTextBlock) {
          print('Assistant: ${block.text}');
        }
      }
    }
    if (event is ClaudeResultEvent) break;
  }

  // Second turn: Recall context
  print('\nTurn 2: Recalling context...');
  final session2 = await client.resumeSession(
    sessionId,
    'What code did I ask you to remember?',
    config,
  );

  await for (final event in session2.events) {
    if (event is ClaudeAssistantEvent) {
      for (final block in event.content) {
        if (block is ClaudeTextBlock) {
          print('Assistant: ${block.text}');
        }
      }
    }
    if (event is ClaudeResultEvent) {
      print('Multi-turn conversation completed.');
      break;
    }
  }
}

/// List all existing sessions in the working directory
Future<void> listExistingSessions(ClaudeClient client) async {
  final sessions = await client.listSessions();

  if (sessions.isEmpty) {
    print('No existing sessions found.');
    return;
  }

  print('Found ${sessions.length} session(s):');
  for (final info in sessions.take(5)) {
    print('  - ${info.sessionId}');
    print('    Created: ${info.timestamp}');
    print('    Updated: ${info.lastUpdated}');
  }
}

/// Example of session cancellation (not run by default)
Future<void> cancelSessionExample(ClaudeClient client) async {
  final config = ClaudeSessionConfig(
    permissionMode: ClaudePermissionMode.bypassPermissions,
  );

  final session = await client.createSession(
    'Count from 1 to 100, one number per line.',
    config,
  );

  var messageCount = 0;
  await for (final event in session.events) {
    if (event is ClaudeAssistantEvent) {
      messageCount++;
      // Cancel after receiving a few messages
      if (messageCount >= 3) {
        print('Cancelling session after $messageCount messages...');
        await session.cancel();
        break;
      }
    }
  }

  print('Session cancelled.');
}
