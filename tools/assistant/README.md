# Assistant

Assistant is a local web client for Codex app-server. Home routes requests to persistent conversations and displays their replies. A Node service keeps queued work running when the browser closes. SQLite stores Home and queue state; Codex stores conversation history. Open `http://127.0.0.1:4180`.

## Start

Requires Node 26+, the Codex CLI on `PATH`, and a signed-in Codex account.

```bash
cd tools/assistant
npm ci
npm start
```

Use `service/install.sh` to install the pinned Cua Driver and its skill, then start Assistant after login on macOS. Run `~/.local/bin/cua-driver permissions grant` to enable computer use in System Settings. Run `service/uninstall.sh` to remove the Assistant service. Assistant state lives in `~/.assistant/assistant.db`; existing Pi conversations are not imported. Run `npm run check` for the TypeScript check.
