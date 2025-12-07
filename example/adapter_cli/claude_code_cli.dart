/// Example demonstrating the Claude Code CLI adapter capabilities.
///
/// This example shows:
/// - Creating a session with configuration options
/// - Streaming events from the session
/// - Capturing session ID for later resumption
/// - Resuming a session with a stored ID
/// - Listing sessions and verifying the captured ID is present
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

  final client = ClaudeCodeCliAdapter();

  // Example 1: Simple single-turn session
  print('=== Example 1: Simple Session ===');
  await simpleSingleTurn(client, workDir);

  // Example 2: Capture session ID and resume later
  print('\n=== Example 2: Capture and Resume Session ===');
  final sessionId = await createAndCaptureSession(client, workDir);
  print('Stored session ID: $sessionId');
  print('(This ID could be persisted to disk/database for later use)\n');
  await resumeStoredSession(client, sessionId, workDir);

  // Example 3: List sessions and verify our session is present
  print('\n=== Example 3: List and Verify Sessions ===');
  await listAndVerifySession(client, sessionId, workDir);
}

/// Simple single-turn session with basic configuration
Future<void> simpleSingleTurn(
  ClaudeCodeCliAdapter client,
  String workDir,
) async {
  final config = ClaudeSessionConfig(
    // Skip permission prompts for automation
    permissionMode: ClaudePermissionMode.bypassPermissions,
    // Limit to single turn
    maxTurns: 1,
  );

  final session = await client.createSession(
    'What is 2 + 2? Reply with just the number.',
    config,
    projectDirectory: workDir,
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

/// Create a session and return the session ID for later resumption.
/// In a real app, you would persist this ID to disk or database.
Future<String> createAndCaptureSession(
  ClaudeCodeCliAdapter client,
  String workDir,
) async {
  final config = ClaudeSessionConfig(
    permissionMode: ClaudePermissionMode.bypassPermissions,
    maxTurns: 1,
  );

  print('Creating session and establishing context...');
  final session = await client.createSession(
    'Remember this code: XYZ123. Just say "OK, I will remember XYZ123".',
    config,
    projectDirectory: workDir,
  );

  // Capture the session ID immediately - this is what you'd store
  final sessionId = session.sessionId;

  await for (final event in session.events) {
    if (event is ClaudeAssistantEvent) {
      for (final block in event.content) {
        if (block is ClaudeTextBlock) {
          print('Assistant: ${block.text}');
        }
      }
    }
    if (event is ClaudeResultEvent) break;
  }

  // Return the session ID so it can be stored and used later
  return sessionId;
}

/// Resume a session using a previously stored session ID.
/// This could be called in a completely separate program execution.
Future<void> resumeStoredSession(
  ClaudeCodeCliAdapter client,
  String sessionId,
  String workDir,
) async {
  final config = ClaudeSessionConfig(
    permissionMode: ClaudePermissionMode.bypassPermissions,
    maxTurns: 1,
  );

  print('Resuming session with stored ID: $sessionId');
  final session = await client.resumeSession(
    sessionId,
    'What code did I ask you to remember?',
    config,
    projectDirectory: workDir,
  );

  await for (final event in session.events) {
    if (event is ClaudeAssistantEvent) {
      for (final block in event.content) {
        if (block is ClaudeTextBlock) {
          print('Assistant: ${block.text}');
        }
      }
    }
    if (event is ClaudeResultEvent) {
      print('Successfully resumed and completed session.');
      break;
    }
  }
}

/// List all sessions and verify the captured session ID is present.
/// This demonstrates that persisted session IDs can be discovered via listSessions.
Future<void> listAndVerifySession(
  ClaudeCodeCliAdapter client,
  String expectedSessionId,
  String workDir,
) async {
  final sessions = await client.listSessions(projectDirectory: workDir);

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

  // Verify the session we created earlier is in the list
  final found = sessions.any((s) => s.sessionId == expectedSessionId);
  if (found) {
    print('\nVerified: Session $expectedSessionId found in list.');
  } else {
    print('\nWarning: Session $expectedSessionId not found in list.');
  }
}

/// Example of session cancellation (not run by default)
Future<void> cancelSessionExample(
  ClaudeCodeCliAdapter client,
  String workDir,
) async {
  final config = ClaudeSessionConfig(
    permissionMode: ClaudePermissionMode.bypassPermissions,
  );

  final session = await client.createSession(
    'Count from 1 to 100, one number per line.',
    config,
    projectDirectory: workDir,
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
