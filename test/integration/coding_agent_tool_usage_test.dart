/// Integration test for tool usage across all coding agents
///
/// Tests that each coding agent can create files via tool usage.
@Tags(['integration'])
library;

import 'dart:io';

import 'package:coding_agents/src/coding_agent/coding_agents.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Test configuration for a coding agent
class AgentTestConfig {
  final String name;
  final CodingAgent Function() createAgent;

  AgentTestConfig({required this.name, required this.createAgent});
}

void main() {
  late Directory testDir;

  setUpAll(() {
    // Create a dedicated test directory
    testDir = Directory(p.join(Directory.current.path, 'tmp', 'tool_usage_test'));
    if (!testDir.existsSync()) {
      testDir.createSync(recursive: true);
    }
  });

  tearDownAll(() {
    // Clean up test directory
    if (testDir.existsSync()) {
      testDir.deleteSync(recursive: true);
    }
  });

  // Define test configurations for each agent
  final agentConfigs = [
    AgentTestConfig(
      name: 'Claude',
      createAgent: () => ClaudeCodingAgent(
        permissionMode: ClaudePermissionMode.bypassPermissions,
      ),
    ),
    AgentTestConfig(
      name: 'Codex',
      createAgent: () => CodexCodingAgent(fullAuto: true),
    ),
    AgentTestConfig(
      name: 'Gemini',
      createAgent: () => GeminiCodingAgent(
        approvalMode: GeminiApprovalMode.yolo,
      ),
    ),
  ];

  for (final config in agentConfigs) {
    group('${config.name} Tool Usage', () {
      test('creates file via tool and emits tool events', () async {
        final agent = config.createAgent();
        final helloFile = File(p.join(testDir.path, 'hello.dart'));

        // Ensure file doesn't exist before test
        if (helloFile.existsSync()) {
          helloFile.deleteSync();
        }

        // Create session
        final session = await agent.createSession(
          projectDirectory: testDir.path,
        );

        // Track events
        var sawToolUse = false;
        String? toolName;

        // Listen to events
        final subscription = session.events.listen((event) {
          switch (event) {
            case CodingAgentToolUseEvent():
              sawToolUse = true;
              toolName = event.toolName;
            default:
              break;
          }
        });

        // Send prompt
        await session.sendMessage(
          'Create a file called hello.dart with a main function that prints "Hello, World!". '
          'Only create the file, do not run it or do anything else.',
        );

        // Wait for turn to complete (with timeout)
        await for (final event in session.events) {
          if (event is CodingAgentTurnEndEvent) break;
        }

        await subscription.cancel();
        await session.close();

        // Verify tool events were emitted
        expect(sawToolUse, isTrue, reason: '${config.name} should emit tool use events');
        expect(toolName, isNotNull, reason: '${config.name} should have a tool name');

        // Verify file was created
        expect(
          helloFile.existsSync(),
          isTrue,
          reason: '${config.name} should create hello.dart file',
        );

        // Verify file has expected content
        final content = helloFile.readAsStringSync();
        expect(
          content.toLowerCase(),
          contains('hello'),
          reason: '${config.name} should create file with Hello content',
        );
        expect(
          content,
          contains('main'),
          reason: '${config.name} should create file with main function',
        );

        // Clean up
        if (helloFile.existsSync()) {
          helloFile.deleteSync();
        }
      }, timeout: Timeout(Duration(minutes: 2)));
    });
  }
}
