# Local protocol

A1R surfaces connect to the runtime on loopback HTTP. The runtime atomically writes `~/.a1r/runtime.json` with protocol version `1`, its port, PID, and a random bearer token. The file is mode 0600 and regenerated at every start.

## Endpoints

- `GET /v1/health` — unauthenticated liveness only
- `GET /v1/setup` — setup state
- `POST /v1/setup/openai` — validate and store an OpenAI key
- `GET /v1/sessions` — recent locally owned sessions
- `GET /v1/sessions/:id/messages` — bounded transcript hydration for thin clients
- `POST /v1/chat` — submit a turn and receive Server-Sent Events
- `POST /v1/cancel` — cancel by client request ID

Every endpoint except health requires `Authorization: Bearer <discovery token>`.

`POST /v1/chat` accepts `text`, optional `sessionId`, optional `cwd`, optional `fresh`, `channel`, `senderId`, and a client-generated `requestId`. The runtime—not the client—decides the work kind, model, tools, memory scope, and final session.

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
