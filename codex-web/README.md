# Codex Web

Local web UI for the manually installed Codex CLI.

## Requirements

- Node.js 20 or newer.
- Codex CLI installed and authenticated on the host.
- Codex CLI configured for non-interactive `codex exec --json` use.

## Run

```shell
npm install
npm run build
npm start
```

Open `http://127.0.0.1:3000`.

Useful environment variables:

- `CODEX_WEB_HOST`: bind host, default `127.0.0.1`.
- `CODEX_WEB_PORT`: bind port, default `3000`.
- `CODEX_WEB_DATA_DIR`: session metadata and event logs, default `.codex-web`.
- `CODEX_BIN`: Codex CLI executable, default `codex`.

## API

- `GET /health`
- `GET /api/info`
- `GET /api/sessions`
- `POST /api/sessions`
- `GET /api/sessions/:id`
- `DELETE /api/sessions/:id`
- `POST /api/sessions/:id/messages`
- `POST /api/sessions/:id/cancel`
- `GET /api/sessions/:id/events`

The event endpoint uses Server-Sent Events and supports `Last-Event-ID`.
Raw Codex JSONL events are preserved as `codex.event` payloads so the UI can
keep working as Codex adds new event shapes.
