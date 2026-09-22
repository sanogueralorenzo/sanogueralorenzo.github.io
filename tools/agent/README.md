# Agent

![Agent banner](assets/agent-banner.png)

Agent is a local assistant for personal and coding work. Home starts tasks in the background and shows short results; open a task for the full conversation.

## Start

Requires Node 22.13+, the Codex CLI, and either an eligible ChatGPT account or an OpenAI API key.

```bash
cd tools/agent
npm install
npm run build
npm link
agent setup
agent chat
```

Use `agent chat --dev` for source reload during development.

## Other clients

- Telegram: `agent telegram setup` pairs a private account and starts the macOS background service. Keep the Mac online.
- macOS 26+: `npm run macos:run` starts the native app. Use Settings to sign in.

See [Local protocol](docs/protocol.md) for runtime and security details.

## Check

```bash
npm run check
swift build --package-path macos
swift run --package-path macos AgentCheck
```

[agent.dev](https://agent.dev)
