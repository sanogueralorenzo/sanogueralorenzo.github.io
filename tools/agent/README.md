# Agent

Agent is a local website for personal and coding work. Home starts tasks in the background and shows short results; open a task for the full conversation.

## Start

Requires Node 22.13+, the Codex CLI, and either an eligible ChatGPT account or an OpenAI API key. Voice recording requires a browser with microphone support; Pin Window currently requires Chrome or Edge.

```bash
cd tools/agent
npm install
npm run build
npm link
agent web
```

`agent web` starts the shared local runtime and opens Agent at `127.0.0.1`. For local UI development, use `npm run web:dev` from this directory. Use Settings in the website to sign in.

See [Local protocol](docs/protocol.md) for runtime and security details.

## Development checks

```bash
npm run typecheck
npm run build
```

[agent.dev](https://agent.dev)
