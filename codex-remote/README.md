## Intro

**Codex Remote** runs a Telegram-to-Codex bridge for remote control of local Codex workflows.

## Quickstart

```shell
../codexhub/scripts/install.sh
./scripts/install.sh
npm install
npm run typecheck
npm run test
```

## Reference

### CLI

```shell
codex-remote --help
codex-remote help start
codex-remote logs --help
```

### Commands (`codex-remote --help`)

```text
install  Install npm dependencies in project root.
start    Start background bot process and persist PID/log state.
stop     Stop managed background bot process.
status   Print managed process status.
restart  Stop and then start managed process.
logs     Show recent logs (or follow with -f).
help     Print this help output.
```

### Telegram Commands

- `/start` and `/help` both show:
  ```text
  Codex Remote

  Commands: /new /resume /delete /help
  Tip: Voice notes work!
  ```
- `/new` starts folder selection for a new thread.
- `/resume` lists threads ordered by latest update first to bind the chat.
- `/delete` lists threads ordered by latest update first to delete.

### Required Config

- `.env`
- `codexhub` on `PATH` (installed by root `./install.sh` or `../codexhub/scripts/install.sh`)
- `codexhub` command surfaces used by remote:
  - `app-server` (for app-server transport)
  - `sessions` (for thread/session operations)
- `CODEXHUB_BIN` (optional override path/name; defaults to `codexhub`)
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ALLOWED_CHAT_IDS` (optional)
- Node dependencies installed in `codex-remote` (`npm install`)

### Voice Note Requirements

- `whisper-cli` on `PATH`
- `ffmpeg` on `PATH`
- Whisper model file at either:
  - `WHISPER_MODEL_PATH_TINY`, or
  - `codex-remote/models/ggml-tiny.en.bin`
- Voice notes use local transcription and will fail if these dependencies are missing.

### Storage

- `runtime/bindings.json`
- `~/.codex/remote/codex-remote.pid`
- `~/.codex/remote/codex-remote.log`
- `~/.codex/remote/codex-remote-caffeinate.pid`

### Output Behavior

- The bot always sends a final Telegram message after each Codex turn.
- If output exceeds Telegram message limits, it is split into ordered chunks and sent sequentially.
- During a running turn, the bot does not emit intermediate turn transcript items.
- At turn completion, it sends only the final assistant turn answer.
- For long-running turns, Telegram `typing` action is refreshed continuously until the final reply/error is posted.

### Thread Delete Behavior

- When Codex marks a thread as pinned, remote delete is skipped and the bot tells you to unpin first.
- Chat-to-thread binding is cleared only when delete succeeds.
