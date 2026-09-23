# Local protocol

The local website and other clients connect to the runtime on loopback HTTP. The runtime atomically writes `~/.agent/runtime.json` with protocol version `1`, its port, PID, and a random bearer token. The file is mode 0600 and regenerated at every start. The website is served by the runtime from that same loopback origin; it receives an HttpOnly, SameSite cookie and never reads the runtime discovery file. The server remains bound to `127.0.0.1`.

If an older runtime is already running, `agent web` starts a small same-origin website proxy that forwards API and event-stream requests with the private runtime token. It leaves the existing runtime and its discovery file untouched. Quitting the website closes the proxy while background work continues.

## Endpoints

- `GET /v1/health` — unauthenticated liveness only
- `GET /` and `/web/*` — local website assets
- `POST /v1/control/quit` — close the website proxy when one is in use; the shared runtime and background work continue
- `GET /v1/artifacts/:id` — view a saved artifact from the private artifact directory
- `GET /v1/setup` — setup state
- `POST /v1/setup/logout` — sign out of the Codex profile shared by Agent, Codex CLI, and the Codex app
- `POST /v1/setup/openai` — connect an OpenAI key through Codex app-server
- `POST /v1/setup/codex/login` — start explicit ChatGPT login with `{ "mode": "browser" | "headless" }`
- `POST /v1/setup/codex/login/:id/wait` — wait for login completion without exposing credentials
- `GET /v1/sessions` — recent sessions, active run IDs, and Home activity entries
- `POST /v1/sessions/auto` — open an exact `preferredSessionId`, or the latest session when none is specified; create one only when no session exists
- `POST /v1/sessions` — create a new session
- `GET /v1/sessions/:id/messages` — saved messages for run recovery
- `POST /v1/attachments` — store up to 25 MB behind an opaque attachment ID
- `POST /v1/runs` — submit to a session and receive its run ID; Home clients may supply a UUID `requestId` for optimistic rendering
- `POST /v1/runs/stop` — stop one run by ID
- `POST /v1/follow-ups` — queue `{ sessionId, text, channel }` for a work conversation
- `POST /v1/follow-ups/remove` — remove a queued `{ sessionId, taskId }`; the returned text can be moved into the composer for editing
- `POST /v1/follow-ups/steer` — send a queued `{ sessionId, taskId, runId }` into that active run; if it has finished, the item stays queued
- `GET /v1/events?sessionId=<id>` — receive that session's snapshot and live events; omit the query for all sessions

Every endpoint except health requires `Authorization: Bearer <discovery token>`.

`POST /v1/attachments` accepts voice-note bytes with `Content-Type` and a URL-encoded `X-Agent-Filename`. Clients open a session before input, then send `text`, `sessionId`, `channel`, and optional `attachmentIds` to `POST /v1/runs`. Paths never cross the upload boundary. The runtime resolves voice notes, memory, and workspace access before sending one turn through Codex app-server.

Agent is a thin coordinator over the Codex App Server launched from the installed Codex runtime. The Agent runtime owns Agent session IDs, saved transcript and memory data, routing, queues, and recovery state. Codex App Server owns model execution, persistent Codex task context, and the tools enabled by the shared Codex profile. Each Agent work session is linked to one persistent Codex task; resuming a session resumes that task. Native Codex capabilities such as Computer Use remain available through the shared Codex App Server path; Agent does not implement a replacement.

Task conversations allow one active run each (`409 busy` for direct overlapping turns). Home accepts concurrent submissions and routes them in submission order. An explicit correction can steer the active Codex turn; an ordinary follow-up enters Agent's durable per-session queue and starts as the next turn. In a direct conversation, typed input during an active run queues a follow-up; an empty composer shows Stop. Home never shows Stop. Queued items remain above the conversation composer until started, removed, or steered. Independent sessions run in parallel, and queued work resumes after a runtime restart. Disconnecting a subscriber never stops work; only an explicit stop by run ID does. The website connects before accepting input and recovers active or missed task runs from a SQLite-backed snapshot after reconnect. A client waiting on a run passes its run ID when reconnecting; the runtime returns the saved handoff if that run moved to another session. There is no event replay buffer. The stream identifies this contract with `X-Agent-Stream: snapshot`.

Each SSE data payload wraps one runtime event with its run ID:

```json
{ "sessionId": "…", "runId": "…", "event": { "type": "text_delta", "delta": "hello" } }
```

Current event types are `snapshot`, `session_activity`, `turn`, `steer`, `queue`, `session`, `navigate`, `status`, `text_delta`, `artifact`, `tool_start`, `tool_end`, `done`, `error`, and `home_entry`/`home_entry_removed`. A Home submission creates one entry per distinct task. A follow-up to the same task updates its card and adds the saved user message to its `requests` list; separate work gets a new card even in the same conversation. A split message can be linked to several cards. Card text and short outcomes may change, while the linked user messages remain saved in the model. Secret-shaped text in saved messages is replaced with `***`. Entries are chronological by latest activity and clickable; only the active entry for a session carries its loading, ready, or attention state. The snapshot contains recent session statuses, the selected session's saved messages and queued tasks, Home entries, active task output/artifacts, and last persisted run state. A scoped subscriber receives its session's turn events, global `session_activity` events, and Home entry updates; `home_entry_removed` removes the provisional card when routing joins an existing task. `turn` and `steer` identify user input and its originating surface. `navigate` carries an `agent://sessions/<id>` deep link and `continues`, which tells clients whether the same run will answer in the destination. Every client preserves visible scrollback, shows an opening boundary, and sends later turns to the destination without replaying its transcript. An artifact carries one runtime-owned local image or file path plus its name, MIME type, and size; clients only deliver or render it. Clients ignore unknown event types so compatible additions do not require lockstep releases.

All events are backend-neutral. Codex app-server notifications such as agent-message deltas, item lifecycle events, and turn completion are normalized before crossing this boundary, so no client imports or implements the app-server protocol.

## Orchestration contract

Each work session is one persistent thread linked to its Agent session and shared Codex profile. Its model and reasoning effort inherit from the active Codex profile. Persistent work threads use `approvalPolicy: never` and the `danger-full-access` sandbox, with the session folder as their working directory or Agent home when no workspace is selected. Home uses separate short-lived `gpt-6-luna` utility turns at low reasoning: a router chooses destinations and whether to start, queue, or steer; a reporter writes short end-of-turn updates. Project and conversation switches use a temporary `gpt-6-luna` utility thread at high reasoning to choose a destination. Utility threads also use `approvalPolicy: never` and `danger-full-access`; their routing/reporting instructions and supplied tools scope their task, but they are not sandboxed read-only. These utility threads do not use the work-session instructions. The router may read a saved conversation to identify it without opening, resuming, or changing it. Personal and coding work use the same prompt, tools, memory, compaction, and event stream. `open_folder` creates a new Agent session rooted at a validated folder; its working directory is used by the persistent thread. The active Codex profile controls available plugins, tools, model settings, Computer Use, and subagent limits. For meaningful code changes, Agent coordinates one writer, parallel read-only reviewers, and one fresh writer for revisions. Keep one writer active at a time for a given code change. When the linked Codex task already has an active writer, Agent surfaces a conflict and does not duplicate or resend the request; retry only after the owning Codex session releases the task.

Agent adds its base instructions, coordinator responsibility, and relevant memory to each work session without changing the Codex profile's `config.toml`. Temporary routing and reporting threads override the profile's instruction file with a neutral utility file and supply their own role-specific base instructions, so they do not inherit work-session instructions. Codex loads project `AGENTS.md` files itself.

## Codex app-server boundary

Agent starts and supervises its own Codex App Server child process; on macOS the default executable is the Codex runtime bundled with ChatGPT.app, and `AGENT_CODEX_COMMAND` can select another executable. It does not attach to the live Codex desktop process. The process uses the shared Codex profile selected by `CODEX_HOME` (or `~/.codex`) and leaves that profile's config, authentication, plugins, and SQLite location intact. Browser, device-code, and API-key setup send `chatgpt`, `chatgptDeviceCode`, and `apiKey` login requests to that shared profile; signing out from Agent also signs out of Codex CLI and the Codex app. Ambient API-key and workload-identity variables are removed from the child process. Agent keeps its SQLite transcripts, memories, project state, and session selection under `~/.agent`, while app-server owns Codex threads and context. If the configured Codex profile changes, Agent clears only its thread-ID links; saved transcripts remain and are available through `read_history`. The old Agent-specific Codex profile has been removed as part of this migration.

The website opens Home by default. A Home request can create a new session or find and resume an existing one, with or without follow-on work. Direct conversations still support a natural-language switch: a temporary turn chooses the destination, and the original request is delivered once there. In-web navigation opens the selected Agent session and continues on its linked Codex task. Agent web does not currently expose Open in Codex navigation because native Codex task IDs are not included in its UI payload. If that navigation is supported later, it must target the linked persistent task and must not replay the transcript into a second task. Clients preserve existing scrollback. The persistent thread can use `read_history` to retrieve earlier saved messages on request. Codex compacts its thread without changing the Agent session or saved transcript.
