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

`agent web` starts or attaches the website to the shared local runtime and opens Agent at `127.0.0.1`. To open it from another device on the same Tailscale network, connect Tailscale on this Mac and run `agent web --tailscale`; it prints a URL using this Mac's Tailscale address. Keep this command running while using Agent from your phone. The runtime API stays on loopback; only the website proxy binds to the Tailscale address. The address and access token are not saved to the repository. For local UI development, use `npm run web:dev` from this directory. Use Settings in the website to sign in.

See [Local protocol](docs/protocol.md) for runtime and security details.

## Development checks

```bash
npm run typecheck
npm run build
```

[agent.dev](https://agent.dev)
