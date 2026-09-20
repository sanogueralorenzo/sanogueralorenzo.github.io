# Agent

![Agent banner](assets/agent-banner.png)

> A quiet, fast personal assistant that can code.

Agent is one local runtime shared by its CLI, Telegram gateway, and native macOS client. It owns sessions, memory, tools, recovery, and client protocol.

## Run

Requires Node 22.13+ and either the Codex CLI with an eligible ChatGPT account or an OpenAI API key.

```bash
cd tools/agent
npm install
npm run build
npm link
agent setup
agent chat --dev
```

Setup offers browser, headless device-code, and API-key connection. Use `agent chat` without `--dev` for normal use.

## Telegram

```bash
agent telegram setup
```

Telegram reuses the existing Agent connection, accepts text or voice notes, pairs one private account through a three-minute link, and installs **Agent** as a macOS user service. The Mac must remain online.

## macOS

```bash
npm run macos:run
```

The SwiftUI app requires macOS 26 and uses the same local runtime as the CLI and Telegram.

## Data and security

Agent stores state under `~/.agent`. ChatGPT and API-key authentication stay inside Agent's private `~/.agent/codex` profile. Telegram credentials use macOS Keychain or a mode-0600 credential file on Linux. Clients connect only through an authenticated loopback endpoint.

## Check

```bash
npm run check
swift build --package-path macos
swift run --package-path macos AgentCheck
```

[agent.dev](https://agent.dev)
