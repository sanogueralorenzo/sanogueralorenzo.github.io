# Local protocol

Agent surfaces connect to the runtime on loopback HTTP. The runtime atomically writes `~/.agent/runtime.json` with protocol version `1`, its port, PID, and a random bearer token. The file is mode 0600 and regenerated at every start.

## Endpoints

- `GET /v1/health` — unauthenticated liveness only
- `GET /v1/setup` — setup state
- `POST /v1/setup/openai` — connect an OpenAI key through Codex app-server
- `POST /v1/setup/codex/login` — start explicit ChatGPT login with `{ "mode": "browser" | "headless" }`
- `POST /v1/setup/codex/login/:id/wait` — wait for login completion without exposing credentials
- `GET /v1/sessions` — recent locally owned sessions
- `GET /v1/sessions/:id/messages` — bounded transcript hydration for thin clients
- `POST /v1/attachments` — store up to 25 MB behind an opaque attachment ID
- `POST /v1/runs` — submit one turn and receive its runtime-assigned run ID
- `POST /v1/runs/stop` — explicitly stop the active run
- `GET /v1/events` — follow the shared live Server-Sent Event stream

Every endpoint except health requires `Authorization: Bearer <discovery token>`.

Telegram does not watch the filesystem or reload itself after builds. During development, run `agent telegram` to restart the background service with the new build.

`POST /v1/attachments` accepts voice-note bytes with `Content-Type` and a URL-encoded `X-Agent-Filename`. `POST /v1/runs` accepts `text`, optional `attachmentIds`, optional `sessionId`, optional `cwd`, optional `fresh`, and `channel`. Paths never cross the upload boundary. The runtime resolves voice notes, session continuity, memory, and workspace access before sending one turn through Codex app-server.

The runtime owns one active run globally. Starting another returns `409 busy`. Disconnecting an event subscriber never stops work; only `POST /v1/runs/stop` cancels it. Clients connect to the live feed before accepting input. Events are not buffered or replayed: a client that was disconnected does not receive earlier live output and reloads completed history from SQLite.

Each SSE data payload wraps one runtime event with its run ID:

```json
{ "runId": "…", "event": { "type": "text_delta", "delta": "hello" } }
```

Current event types are `turn`, `session`, `status`, `text_delta`, `artifact`, `tool_start`, `tool_end`, `done`, and `error`. `turn` identifies the originating surface and lets every connected client render the same user input. An artifact carries one runtime-owned local image or file path plus its name, MIME type, and size; CLI, Telegram, and macOS only render that shared event. Clients ignore unknown event types so compatible additions do not require lockstep releases.

All events are backend-neutral. Codex app-server notifications such as agent-message deltas, item lifecycle events, and turn completion are normalized before crossing this boundary, so no client imports or implements the app-server protocol.

## Orchestration contract

Every Agent session is one persistent `gpt-5.6-luna` thread at high reasoning. Personal and coding work use the same prompt, tools, memory, compaction, and event stream. Sessions without a CLI-established workspace are read-only; that workspace persists when Telegram or macOS resumes the session. Agent's private Codex profile enables up to eight subagents. For meaningful code changes, Luna coordinates one writer, parallel read-only reviewers, and one fresh reviser.

The private profile replaces Codex's built-in base instructions with Agent's short shared prompt. Per-turn developer instructions contain only the coordinator responsibility and relevant memory. Codex loads project `AGENTS.md` files itself.

## Codex app-server boundary

Agent launches `codex app-server` with its default stdio transport, sends `initialize` followed by `initialized`, and communicates using newline-delimited JSON-RPC messages. Browser, device-code, and API-key setup send `chatgpt`, `chatgptDeviceCode`, and `apiKey` login requests respectively. Every mode uses the same persistent thread, turn, tool, compaction, interruption, artifact, and realtime transcription path. The child process receives `CODEX_HOME` and `CODEX_SQLITE_HOME` set to Agent's mode-0700 `codex/` directory; ambient OpenAI and Codex authentication variables are removed. App-server exclusively owns authentication persistence, billing state, model context, and context compaction inside that profile. Agent stores its SQLite transcript, memories, project state, session selection, and opaque Codex thread IDs. Switching authentication changes the account in that profile without selecting another runtime or fallback backend.
