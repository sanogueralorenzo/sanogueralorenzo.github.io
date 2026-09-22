# Local protocol

Agent surfaces connect to the runtime on loopback HTTP. The runtime atomically writes `~/.agent/runtime.json` with protocol version `1`, its port, PID, and a random bearer token. The file is mode 0600 and regenerated at every start.

## Endpoints

- `GET /v1/health` — unauthenticated liveness only
- `GET /v1/setup` — setup state
- `POST /v1/setup/openai` — connect an OpenAI key through Codex app-server
- `POST /v1/setup/codex/login` — start explicit ChatGPT login with `{ "mode": "browser" | "headless" }`
- `POST /v1/setup/codex/login/:id/wait` — wait for login completion without exposing credentials
- `GET /v1/sessions` — recent sessions and each session's active run ID
- `POST /v1/sessions/auto` — open an exact `preferredSessionId`, or the latest session when none is specified; create one only when no session exists
- `POST /v1/sessions` — create a new session
- `POST /v1/telegram/session` — return the `ownerId`'s persisted session or create one with `fresh: true`
- `GET /v1/sessions/:id/messages` — saved messages for run recovery
- `POST /v1/attachments` — store up to 25 MB behind an opaque attachment ID
- `POST /v1/runs` — submit to a session and receive its runtime-assigned run ID
- `POST /v1/runs/stop` — stop one run by ID
- `GET /v1/events?sessionId=<id>` — receive that session's snapshot and live events; omit the query for all sessions

Every endpoint except health requires `Authorization: Bearer <discovery token>`.

Telegram does not watch the filesystem or reload itself after builds. During development, run `agent telegram` to restart the background service with the new build.

`POST /v1/attachments` accepts voice-note bytes with `Content-Type` and a URL-encoded `X-Agent-Filename`. Clients open a session before input, then send `text`, `sessionId`, `channel`, and optional `attachmentIds` to `POST /v1/runs`. Paths never cross the upload boundary. The runtime resolves voice notes, memory, and workspace access before sending one turn through Codex app-server.

Agent owns session IDs, saved transcripts, Telegram's owner-to-session binding, and run state. Codex app-server owns model execution and context. Task conversations allow one active run each (`409 busy` for an overlapping turn); Home accepts independent requests concurrently and dispatches them to background tasks. Disconnecting a subscriber never stops work; only an explicit stop by run ID does. Clients connect before accepting input and recover active or missed task runs from a SQLite-backed snapshot after reconnect. A client waiting on a run passes its run ID when reconnecting; the runtime returns the saved handoff if that run moved to another session. There is no event replay buffer. The stream identifies this contract with `X-Agent-Stream: snapshot`.

Each SSE data payload wraps one runtime event with its run ID:

```json
{ "sessionId": "…", "runId": "…", "event": { "type": "text_delta", "delta": "hello" } }
```

Current event types are `snapshot`, `session_activity`, `turn`, `session`, `navigate`, `status`, `text_delta`, `artifact`, `tool_start`, `tool_end`, `done`, `error`, `task_report`, and `home_error`. Home publishes task reports (working or finished) and dispatch errors, but no thinking stream or completion chatter. The snapshot contains recent session statuses, the selected session's saved messages, task reports, active task output/artifacts, and last persisted run state. A scoped subscriber receives its session's turn events, global `session_activity` events for status refresh, and task reports. `turn` identifies the originating surface. `navigate` carries an `agent://sessions/<id>` deep link and `continues`, which tells clients whether the same run will answer in the destination. Every client preserves visible scrollback, shows an opening boundary, and sends later turns to the destination without replaying its transcript. An artifact carries one runtime-owned local image or file path plus its name, MIME type, and size; clients only deliver or render it. Clients ignore unknown event types so compatible additions do not require lockstep releases.

All events are backend-neutral. Codex app-server notifications such as agent-message deltas, item lifecycle events, and turn completion are normalized before crossing this boundary, so no client imports or implements the app-server protocol.

## Orchestration contract

Every Agent session is one persistent `gpt-5.6-luna` thread at high reasoning. Personal and coding work use the same prompt, tools, memory, compaction, and event stream. Sessions without a workspace are read-only. Project and conversation switches use a temporary, read-only Codex thread to choose a destination. `open_folder` creates a new Agent session rooted at a validated folder; its follow-on turn starts with workspace-write access. Agent's private Codex profile enables up to eight subagents. For meaningful code changes, Luna coordinates one writer, parallel read-only reviewers, and one fresh writer for revisions.

The private profile replaces Codex's built-in base instructions with Agent's short shared prompt. Per-turn developer instructions contain only the coordinator responsibility and relevant memory. Codex loads project `AGENTS.md` files itself.

## Codex app-server boundary

Agent launches `codex app-server` with its default stdio transport, sends `initialize` followed by `initialized`, and communicates using newline-delimited JSON-RPC messages. Browser, device-code, and API-key setup send `chatgpt`, `chatgptDeviceCode`, and `apiKey` login requests respectively. Every mode uses the same persistent thread, turn, tool, compaction, interruption, artifact, and realtime transcription path. The child process receives `CODEX_HOME` and `CODEX_SQLITE_HOME` set to Agent's mode-0700 `codex/` directory; ambient OpenAI and Codex authentication variables are removed. App-server exclusively owns authentication persistence, billing state, model context, and context compaction inside that profile. Agent stores its SQLite transcript, memories, project state, session selection, and opaque Codex thread IDs. Switching authentication changes the account in that profile without selecting another runtime or fallback backend.

Selection stays with a connected client until `/new` or a natural-language switch; activity elsewhere does not switch it. On launch, CLI opens a new provisional session and binds the terminal directory on its first ordinary turn; a routing handoff leaves that session unbound. macOS restores its last selection or opens the latest, and Telegram adopts the latest only when first paired. macOS saves its selected ID locally. A likely switch request may list saved conversations by title and preview, read a candidate if needed, then open a strong match. The temporary turn is not saved; ordinary requests skip it. The pending input is saved before routing so an interruption leaves the request in whichever session owns the run. The source conversation remains intact, except an empty provisional session is removed. A switch with no remaining task only navigates; otherwise the original request, including any transcribed voice note, is delivered once in the destination. The persistent thread can use `read_history` to retrieve earlier saved messages on request. Codex compacts its thread without changing the Agent session or saved transcript.
