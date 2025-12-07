import 'coding_agent_events.dart';
import 'coding_agent_types.dart';

/// Abstract interface for all coding agents
abstract class CodingAgent {
  /// Create a new session in the given project directory
  ///
  /// [approvalHandler] is an optional callback for tool execution approval.
  /// When provided, the agent will invoke this callback when a tool requires
  /// approval. Not all agents support approval handling (e.g., Gemini does not).
  Future<CodingAgentSession> createSession({
    required String projectDirectory,
    ToolApprovalHandler? approvalHandler,
  });

  /// Resume an existing session by ID
  ///
  /// [approvalHandler] is an optional callback for tool execution approval.
  /// When provided, the agent will invoke this callback when a tool requires
  /// approval. Not all agents support approval handling (e.g., Gemini does not).
  Future<CodingAgentSession> resumeSession(
    String sessionId, {
    required String projectDirectory,
    ToolApprovalHandler? approvalHandler,
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
