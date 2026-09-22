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
- `POST /v1/telegram/session` — return the `ownerId`'s persisted session, create one with `fresh: true`, or bind an existing `sessionId`
- `GET /v1/sessions/:id/messages` — bounded transcript hydration for thin clients
- `POST /v1/attachments` — store up to 25 MB behind an opaque attachment ID
- `POST /v1/runs` — submit to a session and receive its runtime-assigned run ID
- `POST /v1/runs/stop` — stop one run by ID
- `GET /v1/events?sessionId=<id>` — receive that session's snapshot and live events; omit the query for all sessions

Every endpoint except health requires `Authorization: Bearer <discovery token>`.

Telegram does not watch the filesystem or reload itself after builds. During development, run `agent telegram` to restart the background service with the new build.

`POST /v1/attachments` accepts voice-note bytes with `Content-Type` and a URL-encoded `X-Agent-Filename`. Clients open a session before input, then send `text`, `sessionId`, `channel`, and optional `attachmentIds` to `POST /v1/runs`. Paths never cross the upload boundary. The runtime resolves voice notes, memory, and workspace access before sending one turn through Codex app-server.

Agent owns session IDs, saved transcripts, Telegram's owner-to-session binding, and run state. Codex app-server owns model execution and context. One run may be active per session; separate sessions run concurrently. Starting another turn in the same session returns `409 busy`. Disconnecting a subscriber never stops work; only an explicit stop by run ID does. Clients connect before accepting input and rehydrate from a SQLite-backed snapshot after reconnect. A deleted source session instead starts with a `navigate` event to its saved destination. There is no event replay buffer. The stream identifies this contract with `X-Agent-Stream: snapshot`.

Each SSE data payload wraps one runtime event with its run ID:

```json
{ "sessionId": "…", "runId": "…", "event": { "type": "text_delta", "delta": "hello" } }
```

Current event types are `snapshot`, `session_activity`, `turn`, `session`, `navigate`, `status`, `text_delta`, `artifact`, `tool_start`, `tool_end`, `done`, and `error`. The snapshot contains recent session statuses, the selected session's saved messages, active output/artifacts, and last persisted run state. A scoped subscriber receives its session's turn events and global `session_activity` events to refresh the conversation list. `turn` identifies the originating surface. `navigate` carries an `agent://sessions/<id>` deep link for opening saved work. An artifact carries one runtime-owned local image or file path plus its name, MIME type, and size; clients only deliver or render it. Clients ignore unknown event types so compatible additions do not require lockstep releases.

All events are backend-neutral. Codex app-server notifications such as agent-message deltas, item lifecycle events, and turn completion are normalized before crossing this boundary, so no client imports or implements the app-server protocol.

## Orchestration contract

Every Agent session is one persistent `gpt-5.6-luna` thread at high reasoning. Personal and coding work use the same prompt, tools, memory, compaction, and event stream. Sessions without a workspace are read-only. The `open_folder` tool saves an existing local folder as the session's working directory; the next turn uses that folder with workspace-write access across all clients. Agent's private Codex profile enables up to eight subagents. For meaningful code changes, Luna coordinates one writer, parallel read-only reviewers, and one fresh writer for revisions.

The private profile replaces Codex's built-in base instructions with Agent's short shared prompt. Per-turn developer instructions contain only the coordinator responsibility and relevant memory. Codex loads project `AGENTS.md` files itself.

## Codex app-server boundary

Agent launches `codex app-server` with its default stdio transport, sends `initialize` followed by `initialized`, and communicates using newline-delimited JSON-RPC messages. Browser, device-code, and API-key setup send `chatgpt`, `chatgptDeviceCode`, and `apiKey` login requests respectively. Every mode uses the same persistent thread, turn, tool, compaction, interruption, artifact, and realtime transcription path. The child process receives `CODEX_HOME` and `CODEX_SQLITE_HOME` set to Agent's mode-0700 `codex/` directory; ambient OpenAI and Codex authentication variables are removed. App-server exclusively owns authentication persistence, billing state, model context, and context compaction inside that profile. Agent stores its SQLite transcript, memories, project state, session selection, and opaque Codex thread IDs. Switching authentication changes the account in that profile without selecting another runtime or fallback backend.

Selection stays with a connected client until `/new` or an explicit open; activity elsewhere does not switch it. On launch, CLI opens the latest session, macOS restores its last selection or opens the latest, and Telegram adopts the latest only when first paired. macOS saves its selected ID locally; Telegram `/sessions` rebinds an existing ID. An unknown explicit ID fails rather than creating a session. The new session's first normal turn can list saved conversations by title and brief preview, read a candidate's messages if needed, then open a strong match. Ordinary requests answer without an extra lookup turn. Opening a match removes the temporary session and Codex thread, records a redirect for reconnecting clients, activates the saved conversation, and emits a deep link. Codex compacts its thread without changing the Agent session or saved transcript.
