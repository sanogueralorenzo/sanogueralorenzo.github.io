# Assistant

Assistant is a local web client for Codex app-server. Home routes requests to persistent conversations and displays their replies. A Node service keeps queued work running when the browser closes. SQLite stores Home and queue state; Codex stores conversation history. Open `http://127.0.0.1:4180`.

## Start

Requires Node 26+, the Codex CLI on `PATH`, and a signed-in Codex account.

```bash
cd tools/assistant
npm ci
npm start
```

Enable the Codex Computer Use plugin in the desktop app and grant its Screen Recording and Accessibility permissions. Run `service/install.sh` to start Assistant after login on macOS, or `service/uninstall.sh` to remove its service. Assistant state lives in `~/.assistant/assistant.db`. Run `npm run check` for the TypeScript check.
