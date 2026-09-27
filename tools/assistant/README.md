# Assistant

Assistant is a local assistant built on Pi. Home routes new requests and follow-ups to persistent session agents, which can delegate read-only research or review. Its Node service keeps conversations and queued work running when the browser closes. Open `http://127.0.0.1:4180`.

## Agentic foundations

The aim is a production-grade agentic system built on five patterns:

1. **Tool use:** choose when to call tools and incorporate their results.
2. **Reflection:** a generator produces output; an evaluator scores and critiques it against the goal; revise until it passes.
3. **Planning and task decomposition:** break complex goals into tasks and alternate reasoning with action.
4. **Orchestrator and workers:** delegate focused tasks to specialized agents, each with a narrow role and its own context.
5. **Memory and context management:** retain useful state across steps and sessions without carrying irrelevant history.

## Start

Requires Node 22+ and a signed-in Codex CLI account in `~/.codex/auth.json`. The Pi CLI is not required.

```bash
cd tools/assistant
npm ci
npm start
```

Use `service/install.sh` to install pinned Cua Driver and its skill, and start Assistant after login on macOS. Run `~/.local/bin/cua-driver permissions grant` to enable computer use in System Settings. Run `service/uninstall.sh` to remove the Assistant service. State lives under `~/.assistant`. Run `npm run check` for the TypeScript check.
