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
    for (final line in data.split('\n')) {
      if (line.trim().isNotEmpty) {
        print('STDOUT: $line');
      }
    }
  });

  // Wait a moment for process to be ready
  await Future.delayed(Duration(milliseconds: 100));

  // Send initialize control request (like the SDK does)
  final initRequest = jsonEncode({
    'request_id': 'init-${DateTime.now().millisecondsSinceEpoch}',
    'type': 'control_request',
    'request': {
      'subtype': 'initialize',
    },
  });

  print('Sending init request: $initRequest');
  process.stdin.writeln(initRequest);
  await process.stdin.flush();
  print('Init request sent');

  // Wait for response
  print('Waiting for init response...');
  await Future.delayed(Duration(seconds: 5));

  print('Done waiting, killing process');
  process.kill();
}
