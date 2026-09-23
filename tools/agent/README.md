# Agent

![Agent banner](assets/agent-banner.png)

Agent is a native macOS app for personal and coding work. Home starts tasks in the background and shows short results; open a task for the full conversation.

## Start

Requires macOS 26+, Node 22.13+, Xcode Command Line Tools, the Codex CLI, and either an eligible ChatGPT account or an OpenAI API key.

```bash
cd tools/agent
npm install
npm run build
npm link
npm run macos:run
```

Use Settings in the app to sign in. The linked `agent serve` command starts the shared local runtime.

See [Local protocol](docs/protocol.md) for runtime and security details.

## Development checks

```bash
npm run check
swift build --package-path macos
swift run --package-path macos AgentCheck
```

[agent.dev](https://agent.dev)
