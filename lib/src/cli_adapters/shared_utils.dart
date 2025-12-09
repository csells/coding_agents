import 'dart:convert';

/// Parses a single line of JSONL input.
///
/// Returns null if the line is empty or doesn't start with '{'.
/// Throws [FormatException] if the line is invalid JSON.
Map<String, dynamic>? parseJsonLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;
  return jsonDecode(trimmed) as Map<String, dynamic>;
}

/// Base exception class for CLI process errors.
///
/// Each adapter has a specific subclass for better error identification.
abstract class CliProcessException implements Exception {
  /// The name of the adapter that threw this exception.
  String get adapterName;

  /// The error message.
  final String message;

  CliProcessException(this.message);

  @override
  String toString() => '$adapterName: $message';
}
