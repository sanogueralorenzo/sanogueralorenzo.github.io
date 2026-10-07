# Assistant

![Assistant Home with Reply and Go-ahead controls](docs/assistant.jpg)

A local assistant built on Pi Durable. Home routes requests to persistent conversations; session agents can delegate read-only research and review. Conversations, child agents, queues, and streamed progress survive service restarts. Interrupted unsafe tools are reported to the model instead of replayed.

Open `http://127.0.0.1:4180`. Reply quotes a selected message; thumbs-up sends “Yes, go ahead.” Queued messages support Edit, Delete, and Steer. Stop preserves waiting work; Continue resumes the stopped request before follow-ups. Tab accepts a saved, tool-free reply suggestion; Escape dismisses it or clears its quote.

## Start

Requires Node 26+ and a signed-in Codex CLI account in `~/.codex/auth.json`.

```bash
cd tools/assistant
npm ci --ignore-scripts
npm start
```

Install Codex Computer Use in the desktop app for native app control. Assistant automatically accepts its approval requests. `service/install.sh` starts Assistant after login on macOS; `service/uninstall.sh` removes the service.

State and transcripts live in `~/.assistant/durable.sqlite`; suggestions live in `~/.assistant/suggestions.db`. Durable uses fresh storage; the previous database and JSONL transcript format are no longer used.

Run `npm run check` and `npm test`. The [instruction benchmark](evals/benchmark/README.md) uses Durable for native agent integration. `npm run eval:suggestions` runs the tool-free suggestion trials with the existing Codex login.
