

AGENT BOARD — Full Requirements & Architecture Spec (v1)

🎯 Purpose

Agent Board provides a phone-friendly, browser-based control panel for managing multiple ACP-based coding agents (Claude Code, Gemini Code, Codex) across multiple local projects on your M4.

It does not expose ACP publicly.

It bridges:

Browser UI → REST/WebSocket → Dart backend → ACP-over-stdio → Local agents



It is a remote shell, dashboard, and session visualizer for your coding agents.


---

🚀 FRONTEND REQUIREMENTS

1. Platform

Built as a Flutter Web app.

Served statically by the same backend service (or uploaded to CDN later).


2. UI Layout (Mobile-first)

Screen: Projects

Card list of projects:

name

path (optional)

last-session status


Tap → Project Detail


Screen: Project Detail

Title bar: project name

Agent selector (tabs/pills):

Claude Code

Gemini

Codex


Prompt input box

Large “Run Agent” button

List of recent sessions (small cards)


Screen: Session Detail

Open via navigation or direct link

Connects to:

wss://<domain>/ws/sessions/<id>

UI sections:

Session metadata (agent, project, timestamps)

Status pill: running/done/failed

Event timeline:

plan

logs

diffs (inline diff viewer)

tool actions

errors



Auto-scroll on new events


Required components

Diff viewer (monospace, inline)

Log scrollback

Timestamp grouping

“Cancel session” button


3. UX Goals

Zero clutter

Big tap targets

Works perfectly on iPhone

60fps scrolling in the event timeline

Works offline once loaded (bonus later)



---

🖥 BACKEND REQUIREMENTS

1. Platform

Dart backend using:

shelf

shelf_router

shelf_web_socket



2. Functionality

Endpoint: GET /api/projects

Returns all configured local projects

Later: editable via UI, configurable via JSON/YAML


Endpoint: GET /api/agents

Returns list of ACP agent definitions:

Claude Code

Gemini

Codex


Each includes:

ID

name

status: running/not-running (later)



Endpoint: POST /api/sessions

Body includes:

{
  "agentId": "claude",
    "projectId": "flutter_ai_toolkit",
      "prompt": "Refactor X"
      }

      Creates session

      Triggers ACP session

      Returns:

      { "id": "sess_xyz", "state": "running" }


      Endpoint: GET /api/sessions/<id>

      Returns metadata only


      Endpoint: GET /api/sessions/<id>/events

      Returns historical event list


      WebSocket: /ws/sessions/<id>

      Streams both historical and new events for that session


      3. Session Model

      Session

      SessionEvent

      SessionState

      Stored in-memory initially, SQLite later


      4. ACP Integration Requirements

      Each ACP agent is a process:

      claude-code-acp

      gemini --experimental-acp

      codex-acp


      Each is connected via acp_dart:

      Using ClientSideConnection

      Using NDJSON over the agent process’s stdio

      One long-lived connection per agent


      Session workflow:

      1. User creates session → backend picks agent + project


      2. Backend sends ACP “start session” messages


      3. ACP sends events:

      plan

      action

      tool result

      diff

      log

      errors



      4. Backend:

      converts to SessionEvent

      stores in memory

      pushes to WebSocket subscribers




      Events MUST be normalized

      Frontend should not need ACP-specific details.


      ---

      🏗 BACKEND ARCHITECTURE

      Matches the single-file implementation you have.

      Layers

      1. HTTP Layer

      Routes via shelf_router

      JSON in/out

      Includes OpenAPI (/openapi.yaml)


      2. WebSocket Layer

      Per-session event stream via shelf_web_socket

      One StreamController<SessionEvent> per session


      3. Agent Registry

      Map<String, AgentClient>

      id: “claude”

      name: “Claude Code”

      process: spawned OS process

      connection: ClientSideConnection

      stream: NDJSON stream



      4. Session Manager

      Creates sessions

      Controls ACP lifecycle

      Receives ACP events

      Emits events

      Tracks state


      5. Data Store

      For v1: In-memory maps

      v2: SQLite file in ~/.agentboard/sessions.db



      ---

      🧪 UNIT TESTING REQUIREMENTS

      To test everything deterministically without spawning real ACP servers, you need:

      ✔ A Mock ACP Agent built with acp_dart

      Mock behavior:

      Accepts ACP client connections

      Implements minimal callbacks:

      initialize

      session/new

      session/prompt → sends fake events (plan, log, diff)


      Able to simulate:

      Success

      Failure

      Slow responses

      Malformed events

      Aborted session



      Mock agent implementation:

      Use ServerSideConnection from acp_dart to implement an in-memory ACP server that the backend can talk to via pipes or dart stream channels.

      Pseudo:

      final stdinController = StreamController<List<int>>();
      final stdoutController = StreamController<List<int>>();

      final server = ServerSideConnection(
        MyMockAgentImplementation(),
          ndJsonStream(stdinController.stream, stdoutController.sink),
          );

          Then wire the backend’s agent client to these mock streams instead of a real process.

          ✔ Tests Needed

          Test 1: POST /api/sessions creates session

          Validate:

          Status 200

          Valid session ID

          Session saved in memory



          Test 2: ACP session runs → events emitted

          Mock agent emits:

          plan

          log

          diff


          Validate backend records each event

          Validate /api/sessions/<id>/events returns them

          Validate WebSocket receives them too


          Test 3: ACP error propagation

          Mock agent sends “error” event

          Backend sets session.state = failed


          Test 4: Cancel session

          Mock session that supports cancellation

          Send session/cancel call

          Validate event + state change


          Test 5: HTTP endpoints match OpenAPI schema

          Validate every route is present

          Validate types returned match schema


          Test 6: No ACP leakage

          Backend should not crash or pass through ACP internals when unexpected messages appear.



          ---

          🌐 DEPLOYMENT PLAN

          M4 Setup:

          Place backend at:

          /usr/local/bin/agentboard_service

          Run with launchd:

          /Library/LaunchDaemons/com.agentboard.service.plist


          HTTPS

          Use Caddy (simplest possible TLS):


          agents.mac.yourdomain.com {
              reverse_proxy localhost:8080
              }

              Firewall

              Expose only:

              443 → backend:8080

              All ACP agents remain on localhost.

              Auto-start agents

              Use launchd for:

              Claude ACP agent

              Gemini ACP agent

              Codex ACP agent




              ---

              📌 NEXT DEVELOPMENT STEPS

              Here’s your actionable sequence.


              ---

              PHASE 1 — Backend + Mock Agent (local dev)

              1. Implement AgentClientManager using acp_dart client side.


              2. Implement MockAcpAgent using acp_dart server side.


              3. Write unit tests (6 categories above).


              4. Wire the stubbed _runStubAcpSession to real ACP calls.


              5. Confirm WebSocket streams update live.




              ---

              PHASE 2 — Real Agents Integration

              Claude Code

              Install: npm i -g @zed-industries/claude-code-acp

              Run ACP server

              Feed stdio to acp_dart


              Gemini

              Enable ACP mode:

              gemini --experimental-acp


              Codex

              Build binary:

              cargo build --release

              Connect via acp_dart


              Test each by manually issuing ACP requests.


              ---

              PHASE 3 — Flutter Web Frontend

              1. Build mobile-friendly UI.


              2. Connect to:

              /api/projects

              /api/agents

              /api/sessions

              /ws/sessions/<id>



              3. Implement:

              Cards

              Diff viewing

              Real-time timeline

              Cancel button




              Test on your iPhone vertically.


              ---

              PHASE 4 — Deployment on M4

              1. Move code to M4 via Cursor Remote SSH.


              2. Install Caddy.


              3. Bind domain to:

              https://agents.mac.<yourdomain>.com


              4. Add auth (token or Cloudflare Access).


              5. Set up launchd service.


              6. Create a lightweight health check.




              ---

              PHASE 5 — Enhancements

              Session persistence via SQLite.

              Multiple workspace roots per project.

              ACP agent crash recovery / auto-reconnect.

              ACP agent metrics (latency, error rate).

              Multi-agent “compare outputs” mode.

              Dark mode.

              Full audit log for agent activity.



              ---

              🎉 You now have the full scope, architecture, and plan for Agent Board.

              This is enough to:

              Begin backend development right now

              Write tests against a mock ACP server

              Build the Flutter web frontend

              Deploy to your M4 as soon as the router arrives

              Extend or harden iteratively


              If you want, I can generate next:

              The full backend with real ACP integration

              The mock ACP server implementation using acp_dart

              The test suite scaffold

              A launchd plist for macOS

              The Flutter web UI starter


              Pick your next piece.