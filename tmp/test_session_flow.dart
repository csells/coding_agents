import 'dart:convert';
import 'dart:io';

void main() async {
  print('Starting Claude process...');

  final process = await Process.start(
    'claude',
    [
      '--output-format', 'stream-json',
      '--input-format', 'stream-json',
      '--dangerously-skip-permissions',
      '--max-turns', '1',
    ],
    workingDirectory: Directory.current.path,
  );

  print('Process started');

  // Listen to stderr
  process.stderr.transform(utf8.decoder).listen((data) {
    print('STDERR: $data');
  });

  // Listen to stdout - look for session_id in init event
  process.stdout.transform(utf8.decoder).listen((data) {
    for (final line in data.split('\n')) {
      if (line.trim().isEmpty) continue;
      print('STDOUT: $line');

      // Parse and look for session_id
      final json = jsonDecode(line) as Map<String, dynamic>;
      if (json['type'] == 'system' && json['subtype'] == 'init') {
        print('\n*** FOUND SESSION ID: ${json['session_id']} ***\n');
      }
    }
  });

  await Future.delayed(Duration(milliseconds: 100));

  // Try user message with empty session_id (like SDK does)
  final userMessage = jsonEncode({
    'type': 'user',
    'session_id': '',  // Empty session_id for first message
    'message': {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': 'Say: "Hello"'},
      ],
    },
    'parent_tool_use_id': null,
  });

  print('Sending user message with empty session_id: $userMessage');
  process.stdin.writeln(userMessage);
  await process.stdin.flush();

  // Wait for response
  print('Waiting for response...');
  await Future.delayed(Duration(seconds: 10));

  print('Done waiting, killing process');
  process.kill();
}
