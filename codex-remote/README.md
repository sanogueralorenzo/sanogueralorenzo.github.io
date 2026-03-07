# codex-remote

Telegram to Codex bridge built with `grammY` + `codex app-server`.

## What it does

- Connects one Telegram chat to one Codex thread.
- Starts new threads, resumes existing threads, and deletes.
- Lists recent threads grouped by working folder with tap-to-resume buttons.
- Supports approvals in Telegram (`Accept`, `Accept Session`, `Decline`, `Cancel`).
- Voice-note transcription (local `whisper-cli`) through `scripts/transcribe-whispercpp.sh`.
- Stores chat->thread bindings in `runtime/bindings.json`.

## Installation

1. Prerequisites

- Node.js 18+
- Codex CLI installed and authenticated (`codex login`)
- Telegram bot token from BotFather
- `ffmpeg` and `whisper-cli` in `PATH` (required for voice notes)

2. Install dependencies

```bash
cd /Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/codex-remote
npm install
```

3. Configure environment

```bash
cp .env.example .env
```

Set at least:

```env
TELEGRAM_BOT_TOKEN=123456:replace-with-your-bot-token
TELEGRAM_ALLOWED_CHAT_IDS=1234567890
WHISPER_MODEL_PATH_TINY=/absolute/path/to/ggml-tiny.en.bin
```

4. Install voice dependencies (macOS/Homebrew)

```bash
brew install ffmpeg whisper-cpp
```

## Run

One-command launcher (macOS/Linux):

```bash
./scripts/codex-remote
```

Development (watch mode):

```bash
npm run dev
```

Build + run:

```bash
npm run build
npm start
```

## Telegram usage

You can use slash commands or plain text shortcuts:

- `new` or `/new` (alias: `n`)
- `resume` or `/resume` (alias: `r`)
- `delete` or `/delete` (alias: `d`)
- `help` or `/help` (alias: `h`)

Flow:

1. Send `new`.
2. Pick a folder from the buttons (ordered by recent thread activity, deduped by cwd).
3. Send your next message to initialize and bind the new thread in that folder.
4. Use `resume` to list/resume existing conversations.

Notes:

- Replies wait up to 5 minutes in foreground. If Codex takes longer, the bot sends the result later as a new message.
- While Codex is generating, the bot streams partial text using Telegram `sendMessageDraft` (best effort, auto-disabled on first draft API error).
- If a bound thread no longer exists, the bot auto-recovers by creating a new thread on next prompt.
- Resuming a thread also sends the latest assistant message from that conversation.
- Deleting the currently bound thread primes the next message to start a new thread.
- If no thread is bound and no new-thread flow is pending, the bot replies with the same help/start response.

## Voice notes

Voice transcription is always enabled and uses `scripts/transcribe-whispercpp.sh`.
If dependencies or model are missing, the bot returns the script/transcriber error in chat.

Set the model path:

```env
WHISPER_MODEL_PATH_TINY=/absolute/path/to/ggml-tiny.en.bin
```

Requirements for the provided script:

- `whisper-cli` in `PATH`
- `ffmpeg` in `PATH`

## Configuration reference

| Variable | Required | Default | Allowed values | Purpose |
| --- | --- | --- | --- | --- |
| `TELEGRAM_BOT_TOKEN` | Yes | none | bot token string | Telegram auth |
| `TELEGRAM_ALLOWED_CHAT_IDS` | No | allow all chats | comma-separated chat ids | only process updates from listed chat ids |
| `CODEX_HOME` | No | `$HOME/.codex` | path | Codex sessions/state location |
| `CODEX_WORKING_DIRECTORY` | No | `$HOME` | path | default working dir for new threads |
| `CODEX_MODEL` | No | Codex default | model id | model override |
| `CODEX_APPROVAL_POLICY` | No | Codex default | `untrusted`, `on-request`, `on-failure`, `never` | approval mode |
| `CODEX_SANDBOX_MODE` | No | Codex default | `read-only`, `workspace-write`, `danger-full-access` | filesystem/process restrictions |
| `CODEX_NETWORK_ACCESS_ENABLED` | No | Codex default | `true`, `false` | network access toggle |
| `WHISPER_MODEL_PATH_TINY` | No | none | path | tiny model path used by `scripts/transcribe-whispercpp.sh` |

Path vars support: `~`, `$HOME`, `${HOME}`.

Fixed defaults (not configurable via env):

- `CODEX_SKIP_GIT_REPO_CHECK=true`
- `CODEX_FORCE_SESSION_SOURCE=vscode`
- `CODEX_FORCE_ORIGINATOR=Codex Desktop`
- `BINDINGS_FILE=runtime/bindings.json`
- `TELEGRAM_VOICE_ECHO_TRANSCRIPT=false`
- `TELEGRAM_DRAFT_STREAMING=true`
- `TELEGRAM_DRAFT_THROTTLE_MS=500`
- `TELEGRAM_APPROVAL_DEFAULT_DECISION=decline`

## Access presets

Safest:

```env
CODEX_APPROVAL_POLICY=on-request
CODEX_SANDBOX_MODE=read-only
CODEX_NETWORK_ACCESS_ENABLED=false
```

Recommended balance:

```env
CODEX_APPROVAL_POLICY=on-request
CODEX_SANDBOX_MODE=workspace-write
CODEX_NETWORK_ACCESS_ENABLED=true
```

Most permissive:

```env
CODEX_APPROVAL_POLICY=never
CODEX_SANDBOX_MODE=danger-full-access
CODEX_NETWORK_ACCESS_ENABLED=true
```

## Project structure

- `src/bot`: Telegram routing, commands, callbacks, keyboards, message copy, middleware
- `src/services`: use-cases (thread actions, prompt execution, voice transcription)
- `src/adapters`: external boundaries (Codex app-server client, session files, bindings store)
- `src/shared`: shared helpers/types
- `runtime`: local runtime files (`bindings.json`, local logs)

## Session source/originator

Session metadata is fixed to `vscode` + `Codex Desktop` so bot-created sessions appear in the default Codex Desktop list.
