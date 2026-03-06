# gateway

Telegram to Codex bridge implemented in Rust (`teloxide` + `codex app-server`).

## What it does

- Connects one Telegram chat to one Codex thread.
- Starts new threads, resumes existing threads, and deletes threads.
- Lists recent threads grouped by working folder with numbered keyboard choices.
- Supports approvals in Telegram (`Accept`, `Accept Session`, `Decline`, `Cancel`).
- Voice-note transcription via local `scripts/transcribe-whispercpp.sh`.
- Stores chat-thread bindings in `runtime/bindings.json`.

## Prerequisites

- Rust toolchain (`cargo`) 1.75+
- Codex CLI installed and authenticated (`codex login`)
- Telegram bot token from BotFather
- `ffmpeg` and `whisper-cli` in `PATH` (for voice notes)

## Setup

```bash
cd /Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/agents/gateway
cp .env.example .env
```

Set at least:

```env
TELEGRAM_BOT_TOKEN=123456:replace-with-your-bot-token
TELEGRAM_ALLOWED_CHAT_IDS=1234567890
WHISPER_MODEL_PATH_TINY=/absolute/path/to/ggml-tiny.en.bin
```

## Run

One-command launcher:

```bash
./scripts/gateway
```

Direct with Cargo:

```bash
cargo run
```

## Build

```bash
cargo build --release
```

## Telegram usage

Commands and text shortcuts:

- `new` or `/new` (alias: `n`)
- `resume` or `/resume` (alias: `r`)
- `delete` or `/delete` (alias: `d`)
- `help` or `/help` (alias: `h`)
- `start` or `/start`

Flow:

1. Send `new`.
2. Pick a folder from the keyboard.
3. Send your message to initialize and bind a thread in that folder.
4. Use `resume` to re-open past conversations.

## Voice notes

Voice transcription is always enabled via `scripts/transcribe-whispercpp.sh`.
If dependencies or the model are missing, the bot returns the transcriber error in chat.

Required env:

```env
WHISPER_MODEL_PATH_TINY=/absolute/path/to/ggml-tiny.en.bin
```

## Configuration reference

| Variable | Required | Default | Purpose |
| --- | --- | --- | --- |
| `TELEGRAM_BOT_TOKEN` | Yes | none | Telegram auth |
| `TELEGRAM_ALLOWED_CHAT_IDS` | No | allow all | Comma-separated allowlist |
| `CODEX_HOME` | No | `$HOME/.codex` | Codex sessions/state location |
| `CODEX_WORKING_DIRECTORY` | No | `$HOME` | Working directory for new threads |
| `CODEX_MODEL` | No | Codex default | Model override |
| `CODEX_APPROVAL_POLICY` | No | Codex default | `untrusted`, `on-request`, `on-failure`, `never` |
| `CODEX_SANDBOX_MODE` | No | Codex default | `read-only`, `workspace-write`, `danger-full-access` |
| `CODEX_NETWORK_ACCESS_ENABLED` | No | Codex default | `true` or `false` |
| `WHISPER_MODEL_PATH_TINY` | No | none | tiny model path for transcription script |

Path vars support: `~`, `$HOME`, `${HOME}`.

Fixed defaults:

- `CODEX_SKIP_GIT_REPO_CHECK=true`
- `CODEX_FORCE_SESSION_SOURCE=vscode`
- `CODEX_FORCE_ORIGINATOR=Codex Desktop`
