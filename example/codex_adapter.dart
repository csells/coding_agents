/// Example demonstrating the Codex CLI adapter capabilities.
///
/// This example shows:
/// - Creating a session with fullAuto mode
/// - Streaming events (thread.started, items, turn.completed)
/// - Multi-turn conversations via resumeSession
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

  final client = CodexClient(cwd: workDir);

  // Example 1: Simple single-turn session with fullAuto
  print('=== Example 1: Simple Session (fullAuto) ===');
  await simpleSingleTurn(client);

  // Example 2: Multi-turn conversation
  print('\n=== Example 2: Multi-Turn Conversation ===');
  await multiTurnConversation(client);

  // Example 3: Custom configuration
  print('\n=== Example 3: Custom Configuration ===');
  await customConfiguration(client);
}

/// Simple single-turn session with fullAuto mode
Future<void> simpleSingleTurn(CodexClient client) async {
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

/// Multi-turn conversation using resumeSession
Future<void> multiTurnConversation(CodexClient client) async {
  final config = CodexSessionConfig(fullAuto: true);

  // First turn: Establish context
  print('Turn 1: Establishing context...');
  final session1 = await client.createSession(
    'Remember this secret word: BANANA. Just confirm you understood.',
    config,
  );

  final threadId = session1.threadId;
  print('Thread ID: $threadId');

  await for (final event in session1.events) {
    if (event is CodexItemCompletedEvent) {
      final item = event.item;
      if (item is CodexAgentMessageItem) {
        print('Assistant: ${item.text}');
      }
    }
    if (event is CodexTurnCompletedEvent) break;
  }

  // Second turn: Recall context
  print('\nTurn 2: Recalling context...');
  final session2 = await client.resumeSession(
    threadId,
    'What was the secret word I asked you to remember?',
    config,
  );

  await for (final event in session2.events) {
    if (event is CodexItemCompletedEvent) {
      final item = event.item;
      if (item is CodexAgentMessageItem) {
        print('Assistant: ${item.text}');
      }
    }
    if (event is CodexTurnCompletedEvent) {
      print('Multi-turn conversation completed.');
      break;
    }
  }
}

/// Example with custom configuration options
Future<void> customConfiguration(CodexClient client) async {
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
Future<void> cancelSessionExample(CodexClient client) async {
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
