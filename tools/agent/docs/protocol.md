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
- `POST /v1/chat` — submit a turn and receive Server-Sent Events
- `POST /v1/cancel` — cancel by client request ID

Every endpoint except health requires `Authorization: Bearer <discovery token>`.

`POST /v1/chat` accepts `text`, optional `sessionId`, optional `cwd`, optional `fresh`, `channel`, `senderId`, and a client-generated `requestId`. The runtime—not the client—decides the work kind, backend, model behavior, tools, memory scope, and final session.

Each SSE data payload is a versioned envelope:

```json
{
  "v": 1,
  "seq": 3,
  "requestId": "client-id",
  "event": { "type": "text_delta", "delta": "hello" }
}
```

Current event types are `session`, `status`, `text_delta`, `tool_start`, `tool_end`, `done`, and `error`. Clients ignore unknown event types so compatible additions do not require lockstep releases.

The `session` event includes `backend: "codex" | "responses"`. All later events are backend-neutral. Codex app-server notifications such as agent-message deltas, item lifecycle events, and turn completion are normalized before crossing this boundary, so no client imports or implements the app-server protocol.

## Codex app-server boundary

Agent launches `codex app-server` with its default stdio transport, sends `initialize` followed by `initialized`, and communicates using newline-delimited JSON-RPC messages. Only documented account, rate-limit, thread, turn, interrupt, and login methods are used. Browser mode sends `{ "type": "chatgpt" }`, intentionally retaining app-server's default local success page. Headless mode sends `{ "type": "chatgptDeviceCode" }` and returns only the verification URL and one-time code required by the client. The child process receives `CODEX_HOME` and `CODEX_SQLITE_HOME` set to Agent's mode-0700 `codex/` directory; ambient OpenAI and Codex authentication variables are removed. App-server exclusively owns authentication persistence and billing state inside that profile. Agent stores only the explicitly selected backend and the opaque thread ID associated with an Agent session. Failed authentication never changes the selected backend or Agent-owned state.
