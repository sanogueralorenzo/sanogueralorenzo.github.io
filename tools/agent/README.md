# Agent

Agent is a local website for personal and coding work. Home starts tasks in the background and shows short results; click a Home message to open its full conversation.

## Start

Requires Node 22.13+, a Codex runtime, and either an eligible ChatGPT account or an OpenAI API key. On macOS Agent uses the Codex runtime bundled with ChatGPT.app by default; set `AGENT_CODEX_COMMAND` to use another executable. On other platforms, `codex` must be available on `PATH`. Voice recording requires a browser with microphone support; Pin Window currently requires Chrome or Edge.

```bash
cd tools/agent
npm install
npm run build
npm link
agent web
```

`agent web` starts or attaches the website to the shared local runtime and opens Agent at `127.0.0.1`. For local UI development, use `npm run web:dev` from this directory. Use Settings in the website to sign in.

Agent is a thin coordinator over Codex App Server. It launches its own app-server process using the shared Codex profile (`CODEX_HOME`, or `~/.codex`); it does not attach to the live Codex desktop process. Each Agent work session resumes one persistent Codex task in that profile. Native Computer Use continues to come from Codex; Agent does not replace it. Agent web does not currently expose Open in Codex navigation. Signing out from Agent also signs out of the shared profile used by Codex CLI and the Codex app.

See [Local protocol](docs/protocol.md) for runtime and security details.

## Development checks

```bash
npm run typecheck
npm run build
```

[agent.dev](https://agent.dev)
