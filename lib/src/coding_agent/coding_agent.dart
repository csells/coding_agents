import 'coding_agent_events.dart';
import 'coding_agent_types.dart';

/// Abstract interface for all coding agents
abstract class CodingAgent {
  /// Create a new session in the given project directory
  Future<CodingAgentSession> createSession({
    required String projectDirectory,
  });

  /// Resume an existing session by ID
  Future<CodingAgentSession> resumeSession(
    String sessionId, {
    required String projectDirectory,
  });

  /// List available sessions for the project directory
  Future<List<CodingAgentSessionInfo>> listSessions({
    required String projectDirectory,
  });
}

/// A coding agent session with multi-turn conversation support
abstract class CodingAgentSession {
  /// Unique session identifier
  ///
  /// Note: This may be empty until the first turn starts and the session ID
  /// is received from the underlying CLI.
  String get sessionId;

  /// Continuous stream of events across all turns
  Stream<CodingAgentEvent> get events;

  /// Send a message and start a new turn
  ///
  /// Returns a [CodingAgentTurn] that can be used to cancel the turn.
  /// Throws [StateError] if called while a turn is already in progress.
  Future<CodingAgentTurn> sendMessage(String prompt);

  /// Get the full history of events for this session
  Future<List<CodingAgentEvent>> getHistory();

  /// Close the session and release resources
  Future<void> close();
}

/// Represents a single turn within a session
abstract class CodingAgentTurn {
  /// Turn identifier (monotonically increasing within session)
  int get turnId;

  /// Cancel the current turn
  Future<void> cancel();
}
