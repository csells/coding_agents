/// Example demonstrating the Codex CLI adapter capabilities.
///
/// This example shows:
/// - Creating a session with fullAuto mode
/// - Streaming events (thread.started, items, turn.completed)
/// - Capturing thread ID for later resumption
/// - Resuming a session with a stored thread ID
/// - Listing sessions and verifying the captured ID is present
/// - Configuration options (model, approval policy, sandbox)
///
/// Prerequisites:
/// - Codex CLI must be installed and authenticated
/// - Run from a directory where Codex has permission to operate
library;

import 'dart:io';

import 'package:coding_agents/coding_agents.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  // Use tmp/ folder to avoid polluting the project
  final workDir = p.join(Directory.current.path, 'tmp');
  Directory(workDir).createSync(recursive: true);

  final client = CodexCliAdapter(cwd: workDir);

  // Example 1: Simple single-turn session with fullAuto
  print('=== Example 1: Simple Session (fullAuto) ===');
  await simpleSingleTurn(client);

  // Example 2: Capture thread ID and resume later
  print('\n=== Example 2: Capture and Resume Session ===');
  final threadId = await createAndCaptureSession(client);
  print('Stored thread ID: $threadId');
  print('(This ID could be persisted to disk/database for later use)\n');
  await resumeStoredSession(client, threadId);

  // Example 3: List sessions and verify our session is present
  print('\n=== Example 3: List and Verify Sessions ===');
  await listAndVerifySession(client, threadId);

  // Example 4: Custom configuration
  print('\n=== Example 4: Custom Configuration ===');
  await customConfiguration(client);
}

/// Simple single-turn session with fullAuto mode
Future<void> simpleSingleTurn(CodexCliAdapter client) async {
  final config = CodexSessionConfig(
    // fullAuto skips approval and sandbox for automation
    fullAuto: true,
  );

  final session = await client.createSession(
    'What is the capital of France? Reply in one word.',
    config,
  );

  print('Thread ID: ${session.threadId}');

  // Process events from the session
  await for (final event in session.events) {
    if (event is CodexThreadStartedEvent) {
      print('Thread started: ${event.threadId}');
    } else if (event is CodexItemCompletedEvent) {
      final item = event.item;
      if (item is CodexAgentMessageItem) {
        print('Assistant: ${item.text}');
      } else if (item is CodexToolCallItem) {
        print('Tool call: ${item.name}');
        if (item.output != null) {
          print('  Output: ${item.output}');
        }
      }
    } else if (event is CodexTurnCompletedEvent) {
      print('Turn completed');
      if (event.usage != null) {
        print(
          '  Tokens: ${event.usage!.inputTokens} in / '
          '${event.usage!.outputTokens} out',
        );
      }
      break;
    } else if (event is CodexErrorEvent) {
      print('Error: ${event.message}');
      break;
    }
  }
}

/// Create a session and return the thread ID for later resumption.
/// In a real app, you would persist this ID to disk or database.
Future<String> createAndCaptureSession(CodexCliAdapter client) async {
  final config = CodexSessionConfig(fullAuto: true);

  print('Creating session and establishing context...');
  final session = await client.createSession(
    'Remember this secret word: BANANA. Just confirm you understood.',
    config,
  );

  // Capture the thread ID immediately - this is what you'd store
  final threadId = session.threadId;

  await for (final event in session.events) {
    if (event is CodexItemCompletedEvent) {
      final item = event.item;
      if (item is CodexAgentMessageItem) {
        print('Assistant: ${item.text}');
      }
    }
    if (event is CodexTurnCompletedEvent) break;
  }

  // Return the thread ID so it can be stored and used later
  return threadId;
}

/// Resume a session using a previously stored thread ID.
/// This could be called in a completely separate program execution.
Future<void> resumeStoredSession(
  CodexCliAdapter client,
  String threadId,
) async {
  final config = CodexSessionConfig(fullAuto: true);

  print('Resuming session with stored thread ID: $threadId');
  final session = await client.resumeSession(
    threadId,
    'What was the secret word I asked you to remember?',
    config,
  );

  await for (final event in session.events) {
    if (event is CodexItemCompletedEvent) {
      final item = event.item;
      if (item is CodexAgentMessageItem) {
        print('Assistant: ${item.text}');
      }
    }
    if (event is CodexTurnCompletedEvent) {
      print('Successfully resumed and completed session.');
      break;
    }
  }
}

/// List all sessions and verify the captured thread ID is present.
/// This demonstrates that persisted thread IDs can be discovered via listSessions.
Future<void> listAndVerifySession(
  CodexCliAdapter client,
  String expectedThreadId,
) async {
  final sessions = await client.listSessions();

  if (sessions.isEmpty) {
    print('No existing sessions found.');
    return;
  }

  print('Found ${sessions.length} session(s):');
  for (final info in sessions.take(5)) {
    print('  - ${info.threadId}');
    print('    Created: ${info.timestamp}');
    print('    Updated: ${info.lastUpdated}');
  }

  // Verify the session we created earlier is in the list
  final found = sessions.any((s) => s.threadId == expectedThreadId);
  if (found) {
    print('\nVerified: Session $expectedThreadId found in list.');
  } else {
    print('\nWarning: Session $expectedThreadId not found in list.');
  }
}

/// Example with custom configuration options
Future<void> customConfiguration(CodexCliAdapter client) async {
  final config = CodexSessionConfig(
    // Explicit approval policy instead of fullAuto
    fullAuto: false,
    approvalPolicy: CodexApprovalPolicy.onFailure,
    sandboxMode: CodexSandboxMode.workspaceWrite,
    // Enable web search
    enableWebSearch: true,
    // Config overrides for model parameters
    configOverrides: ['model_reasoning_effort="high"'],
  );

  final session = await client.createSession(
    'What is 15 * 17? Show your work.',
    config,
  );

  print('Thread ID: ${session.threadId}');

  await for (final event in session.events) {
    if (event is CodexItemCompletedEvent) {
      final item = event.item;
      if (item is CodexAgentMessageItem) {
        print('Assistant: ${item.text}');
      }
    }
    if (event is CodexTurnCompletedEvent) {
      print('Turn completed.');
      break;
    }
  }
}

/// Example of session cancellation (not run by default)
Future<void> cancelSessionExample(CodexCliAdapter client) async {
  final config = CodexSessionConfig(fullAuto: true);

  final session = await client.createSession(
    'List all prime numbers under 1000.',
    config,
  );

  var messageCount = 0;
  await for (final event in session.events) {
    if (event is CodexItemCompletedEvent) {
      messageCount++;
      if (messageCount >= 5) {
        print('Cancelling session after $messageCount items...');
        await session.cancel();
        break;
      }
    }
  }

  print('Session cancelled.');
}
