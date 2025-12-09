import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'gemini_events.dart';
import 'gemini_session.dart';
import 'gemini_types.dart';

// Re-export GeminiProcessException from session for backwards compatibility
export 'gemini_session.dart' show GeminiProcessException;

/// Client for interacting with Gemini CLI
class GeminiCliAdapter {
  int _turnCounter = 0;

  GeminiCliAdapter();

  /// List all sessions for a project directory
  ///
  /// Parses the text output from `gemini --list-sessions` which has format:
  /// ```
  /// Available sessions for this project (N):
  ///   1. Prompt text (time ago) [session-uuid]
  /// ```
  Future<List<GeminiSessionInfo>> listSessions({
    required String projectDirectory,
  }) async {
    final result = await Process.run('gemini', [
      '--list-sessions',
    ], workingDirectory: projectDirectory);

    if (result.exitCode != 0) {
      throw GeminiProcessException('Failed to list sessions: ${result.stderr}');
    }

    // Gemini CLI writes list output to stderr
    final output = result.stderr as String;
    if (output.trim().isEmpty) return [];

    final sessions = <GeminiSessionInfo>[];
    final now = DateTime.now();

    // Pattern: "  1. Prompt text (time ago) [session-uuid]"
    final linePattern = RegExp(
      r'^\s*\d+\.\s+.+\s+\(([^)]+)\)\s+\[([a-f0-9-]+)\]$',
    );

    for (final line in output.split('\n')) {
      final match = linePattern.firstMatch(line);
      if (match != null) {
        final timeAgo = match.group(1)!;
        final sessionId = match.group(2)!;

        // Parse relative time to approximate DateTime
        final timestamp = _parseRelativeTime(timeAgo, now);

        sessions.add(
          GeminiSessionInfo(
            sessionId: sessionId,
            projectHash: '', // Not available from CLI output
            startTime: timestamp,
            lastUpdated: timestamp,
            messageCount: 0, // Not available from CLI output
          ),
        );
      }
    }

    return sessions;
  }

  /// Get the full history of events for a session
  ///
  /// Parses the session JSON file and returns all events in order.
  /// Gemini stores sessions as JSON files with a messages array.
  /// Only returns history for sessions that match the given projectDirectory.
  /// Throws [GeminiProcessException] if the session file is not found.
  Future<List<GeminiEvent>> getSessionHistory(
    String sessionId, {
    required String projectDirectory,
  }) async {
    final geminiDir = Directory('${Platform.environment['HOME']}/.gemini/tmp');

    if (!await geminiDir.exists()) {
      throw GeminiProcessException('Session not found: $sessionId');
    }

    // Compute the project hash to find the correct directory
    final projectHash = _computeProjectHash(projectDirectory);
    final projectSessionsDir = Directory(
      '${geminiDir.path}/$projectHash/chats',
    );

    if (!await projectSessionsDir.exists()) {
      throw GeminiProcessException('Session not found: $sessionId');
    }

    // Find the session file in the project's chats directory
    File? sessionFile;
    await for (final file in projectSessionsDir.list()) {
      if (file is! File || !file.path.endsWith('.json')) continue;

      // Read file and check sessionId
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      if (json['sessionId'] == sessionId) {
        sessionFile = file;
        break;
      }
    }

    if (sessionFile == null) {
      throw GeminiProcessException('Session not found: $sessionId');
    }

    // Parse the JSON file
    final content = await sessionFile.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final messages = json['messages'] as List<dynamic>? ?? [];

    final events = <GeminiEvent>[];
    var turnId = 0;

    // Add init event
    events.add(
      GeminiInitEvent(sessionId: sessionId, turnId: turnId, model: ''),
    );

    // Convert messages to events
    for (final msg in messages) {
      final msgMap = msg as Map<String, dynamic>;
      final type = msgMap['type'] as String?;
      final msgContent = msgMap['content'] as String? ?? '';
      final timestamp = DateTime.tryParse(msgMap['timestamp'] as String? ?? '');

      if (type == 'user') {
        events.add(
          GeminiMessageEvent(
            sessionId: sessionId,
            turnId: turnId,
            role: 'user',
            content: msgContent,
            delta: false,
            timestamp: timestamp,
          ),
        );
      } else if (type == 'gemini') {
        events.add(
          GeminiMessageEvent(
            sessionId: sessionId,
            turnId: turnId,
            role: 'assistant',
            content: msgContent,
            delta: false,
            timestamp: timestamp,
          ),
        );

        // Add a result event after assistant message to mark turn complete
        events.add(
          GeminiResultEvent(
            sessionId: sessionId,
            turnId: turnId,
            status: 'success',
            timestamp: timestamp,
          ),
        );
        turnId++;
      }
    }

    return events;
  }

  /// Parse relative time strings like "1 hour ago", "Just now", "2 days ago"
  DateTime _parseRelativeTime(String timeAgo, DateTime now) {
    final lower = timeAgo.toLowerCase();

    if (lower == 'just now') {
      return now;
    }

    final pattern = RegExp(
      r'(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago',
    );
    final match = pattern.firstMatch(lower);

    if (match != null) {
      final amount = int.parse(match.group(1)!);
      final unit = match.group(2)!;

      switch (unit) {
        case 'second':
          return now.subtract(Duration(seconds: amount));
        case 'minute':
          return now.subtract(Duration(minutes: amount));
        case 'hour':
          return now.subtract(Duration(hours: amount));
        case 'day':
          return now.subtract(Duration(days: amount));
        case 'week':
          return now.subtract(Duration(days: amount * 7));
        case 'month':
          return now.subtract(Duration(days: amount * 30));
        case 'year':
          return now.subtract(Duration(days: amount * 365));
      }
    }

    // Default to now if we can't parse
    return now;
  }

  /// Compute the project hash used by Gemini CLI for session storage
  ///
  /// Gemini CLI stores sessions in `~/.gemini/tmp/{projectHash}/chats/`
  /// where projectHash is the SHA-256 hash of the project directory path.
  String _computeProjectHash(String projectDirectory) {
    final bytes = utf8.encode(projectDirectory);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Create a new Gemini session
  ///
  /// Returns a [GeminiSession] that provides access to the event stream.
  /// Call [GeminiSession.send] to send the first prompt after subscribing
  /// to the event stream.
  GeminiSession createSession(
    GeminiSessionConfig config, {
    required String projectDirectory,
  }) {
    final turnId = _turnCounter++;
    return GeminiSession.create(
      config: config,
      projectDirectory: projectDirectory,
      turnId: turnId,
    );
  }

  /// Resume an existing session
  ///
  /// Returns a [GeminiSession] for the resumed session.
  /// Call [GeminiSession.send] to send the prompt after subscribing
  /// to the event stream.
  GeminiSession resumeSession(
    String sessionId,
    GeminiSessionConfig config, {
    required String projectDirectory,
  }) {
    final turnId = _turnCounter++;
    return GeminiSession.createForResume(
      sessionId: sessionId,
      config: config,
      projectDirectory: projectDirectory,
      turnId: turnId,
    );
  }
}
