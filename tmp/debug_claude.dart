import 'dart:convert';
import 'dart:io';

void main() async {
  print('Starting Claude process...');

  // Need BOTH --output-format and --input-format for bidirectional JSONL
  final process = await Process.start(
    'claude',
    [
      '--output-format', 'stream-json',
      '--input-format', 'stream-json',
      '--dangerously-skip-permissions',
    ],
    workingDirectory: Directory.current.path,
  );

  print('Process started');

  // Listen to stderr
  process.stderr.transform(utf8.decoder).listen((data) {
    print('STDERR: $data');
  });

  // Listen to stdout
  process.stdout.transform(utf8.decoder).listen((data) {
    print('STDOUT: $data');
  });

  // Wait a moment for process to be ready
  await Future.delayed(Duration(milliseconds: 500));

  // Correct message format (matches output format):
  // {"type":"user","message":{"role":"user","content":[{"type":"text","text":"..."}]}}
  final message = jsonEncode({
    'type': 'user',
    'message': {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': 'Say exactly: "Hello"'},
      ],
    },
  });

  print('Sending message: $message');
  process.stdin.writeln(message);
  await process.stdin.flush();
  print('Message sent');

  // Wait for response
  print('Waiting for response...');
  await Future.delayed(Duration(seconds: 30));

  print('Done waiting, killing process');
  process.kill();
}
