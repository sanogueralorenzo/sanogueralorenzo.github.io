# Local protocol

Agent surfaces connect to the runtime on loopback HTTP. The runtime atomically writes `~/.agent/runtime.json` with protocol version `1`, its port, PID, and a random bearer token. The file is mode 0600 and regenerated at every start.

## Endpoints

- `GET /v1/health` — unauthenticated liveness only
- `GET /v1/setup` — setup state
- `POST /v1/setup/openai` — validate and store an OpenAI key
- `POST /v1/setup/backend` — select `codex` or `responses`
- `POST /v1/setup/codex/login` — start explicit ChatGPT login with `{ "mode": "browser" | "headless" }`
- `GET /v1/setup/codex/login/:id` — poll a login attempt without exposing credentials
- `POST /v1/setup/codex/login/:id/cancel` — cancel a pending browser or headless login
- `GET /v1/sessions` — recent locally owned sessions
- `GET /v1/sessions/:id/messages` — bounded transcript hydration for thin clients
- `POST /v1/attachments` — store up to 25 MB behind an opaque attachment ID
- `POST /v1/chat` — submit a turn and receive Server-Sent Events
- `POST /v1/cancel` — cancel by client request ID
- `POST /v1/runtime/restart` — request an idle-only graceful runtime restart

Every endpoint except health requires `Authorization: Bearer <discovery token>`.

The runtime rejects restart requests while any turn is active. The Telegram background gateway watches Agent's own runtime sources, waits until the requesting reply is delivered, runs the full check and production build, then requests this graceful restart and exits. The macOS user service relaunches the gateway, which reconnects to the same SQLite-backed sessions and sends a short confirmation. A failed check leaves the current runtime running.

`POST /v1/attachments` accepts raw bytes with `Content-Type` and a URL-encoded `X-Agent-Filename`. `POST /v1/chat` accepts `text`, optional `attachmentIds`, optional `sessionId`, optional `cwd`, optional `fresh`, `channel`, `senderId`, and a client-generated `requestId`. Paths never cross the upload boundary. The runtime resolves attachments, transcribes audio through the explicitly selected backend, then decides the work kind, model behavior, tools, memory scope, and final session from the transcript.

Each SSE data payload is a versioned envelope:

```json
{
  "v": 1,
  "seq": 3,
  "requestId": "client-id",
  "event": { "type": "text_delta", "delta": "hello" }
}
```

Current event types are `session`, `status`, `text_delta`, `artifact`, `tool_start`, `tool_end`, `done`, and `error`. An artifact carries one runtime-owned local image or file path plus its name, MIME type, and size; CLI, Telegram, and macOS only render that shared event. Clients ignore unknown event types so compatible additions do not require lockstep releases.

The `session` event includes `backend: "codex" | "responses"`. All later events are backend-neutral. Codex app-server notifications such as agent-message deltas, item lifecycle events, and turn completion are normalized before crossing this boundary, so no client imports or implements the app-server protocol.

## Orchestration contract

Every Agent session has one persistent `gpt-5.6-luna` coordinator running at high reasoning. Bounded tasks may run first on an isolated Luna-high worker; coding and implementation run on an isolated `gpt-5.6-sol` high worker. Worker output is private working material returned to the coordinator for the single user-facing response.

`gpt-6-astra` high is gated by an explicit request for Astra in the current user message and is never selected by automatic routing. Agent's private Codex profile disables Codex-native automatic subagent spawning so both the ChatGPT and API-key backends follow this same policy without fallback behavior.

## Codex app-server boundary

Agent launches `codex app-server` with its default stdio transport, sends `initialize` followed by `initialized`, and communicates using newline-delimited JSON-RPC messages. Only documented account, rate-limit, thread, turn, interrupt, login, and realtime methods are used. Browser mode sends `{ "type": "chatgpt" }`, intentionally retaining app-server's default local success page. Headless mode sends `{ "type": "chatgptDeviceCode" }` and returns only the verification URL and one-time code required by the client. Subscription voice transcription sends the original Opus media through app-server's private v3 WebRTC session and consumes its user-transcript event; API-key mode uses OpenAI's transcription endpoint. Neither mode switches backend or falls back to local speech software. The child process receives `CODEX_HOME` and `CODEX_SQLITE_HOME` set to Agent's mode-0700 `codex/` directory; ambient OpenAI and Codex authentication variables are removed. App-server exclusively owns authentication persistence and billing state inside that profile. Agent stores only the explicitly selected backend and the opaque thread ID associated with an Agent session. Failed authentication never changes the selected backend or Agent-owned state.
