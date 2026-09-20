# A1R

![A1R banner](assets/a1r-banner.png)

> A quiet, fast personal assistant that can code.

A1R is one local runtime shared by its CLI, Telegram gateway, and native macOS client. It owns routing, sessions, memory, tools, recovery, and client protocol.

## Run

Requires Node 22.13+ and either the Codex CLI with an eligible ChatGPT account or an OpenAI API key.

```bash
cd tools/a1r
npm install
npm run build
npm link
a1r setup
a1r chat --dev
```

Setup offers browser, headless device-code, and API-key connection. Use `a1r chat` without `--dev` for normal use.

## Telegram

```bash
a1r telegram setup
```

Telegram reuses the existing A1R connection, pairs one private account through a three-minute link, and installs **A1R Gateway** as a macOS user service. The Mac must remain online.

## macOS

```bash
npm run macos:run
```

The SwiftUI app launches and uses the same local runtime as the CLI and Telegram.

## Data and security

A1R stores state under `~/.a1r`. ChatGPT authentication stays inside A1R's private `~/.a1r/codex` profile. Secrets use macOS Keychain or a mode-0600 credential file on Linux. Clients connect only through an authenticated loopback endpoint.

## Check

```bash
npm run check
swift build --package-path macos
swift run --package-path macos A1RProtocolCheck
```

[a1r.dev](https://a1r.dev)
