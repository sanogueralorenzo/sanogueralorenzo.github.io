# Assistant

Assistant is a local personal and coding assistant powered by the pinned Pi SDK. One Node service owns Home routing, persistent Pi conversations, queues, and updates. The website at `http://127.0.0.1:4180` is its first client; closing the tab does not stop work.

## Start

Requires Node 22+ and a signed-in Codex CLI account in `~/.codex/auth.json`. The Pi CLI is not required. Assistant keeps a private, renewable copy of that Codex credential in its data directory; it does not change Pi's separate login.

```bash
cd tools/assistant
npm ci
npm start
```

To run automatically after login on macOS or Linux, use `service/install.sh`. Run `service/uninstall.sh` to remove the background service. Set `ASSISTANT_PORT`, `ASSISTANT_DATA_DIR`, `ASSISTANT_WORKSPACE`, or `ASSISTANT_CONCURRENCY` before a manual start to override defaults. The service stores its state under `${XDG_DATA_HOME:-~/.local/share}/assistant` and Pi session files under its `sessions` directory.

Home accepts overlapping requests immediately. The Pi coordinator chooses a saved conversation or creates one or more new conversations; independent outcomes get separate clickable Home entries. A conversation accepts queued follow-ups and explicit steering, with one active turn at a time. Every result returns to its Home entry. On restart, an in-flight turn is marked interrupted and can be continued manually from Home. Queued work survives the restart.

All roles use the Codex `gpt-6-luna` model with Fast processing. Home routing uses Low reasoning. The reporter and task agents use High reasoning. The coordinator assigns a persistent task agent: **personal** for everyday help, **code** for implementation, **scout** for read-only investigation, or **reviewer** for read-only review. Each has its own base instructions and tool access; the conversation header shows its role. Other model providers are outside this version.

Run `npm run check` for the focused TypeScript check. There is no test suite or non-site CI.
