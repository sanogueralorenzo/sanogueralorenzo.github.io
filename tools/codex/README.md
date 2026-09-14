## Intro

**Codex Remote** runs a Telegram-to-Codex bridge for remote control of local Codex workflows.

## Quickstart

```shell
./scripts/install.sh
npm install
npm run generate:app-server-types
npm run typecheck
npm run test
```

## Reference

### CLI

```shell
codexbot --help
codexbot help start
codexbot logs --help
```

### Commands (`codexbot --help`)

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

  Commands: /new /resume /delete /goal /help
  Tip: Voice notes work!
  ```
- `/new` starts folder selection for a new thread.
- `/resume` lists threads ordered by latest update first in the message body and shows numeric reply buttons to bind the chat.
- `/delete` lists threads ordered by latest update first in the message body and shows numeric reply buttons to delete.
- `/goal` shows the current goal for the bound thread.
- `/goal <objective>` sets the bound thread goal and marks it active.
- `/goal pause`, `/goal resume`, and `/goal clear` update or clear the bound thread goal.

### Required Config

- `.env`
- `codex` on `PATH` for app-server transport and thread/session operations
- `CODEX_BIN` (optional Codex CLI override; defaults to `codex`)
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ALLOWED_CHAT_IDS` (optional)
- Node dependencies installed in `codexbot` (`npm install`)

### App Server Protocol Types

- `npm run generate:app-server-types` refreshes generated TypeScript protocol types from `codex app-server generate-ts --experimental`.
- `npm run typecheck` first runs `npm run check:app-server-types` and fails when committed generated types are stale.

### Voice Note Requirements

- `whisper-cli` on `PATH`
- `ffmpeg` on `PATH`
- Whisper model file at either:
  - `WHISPER_MODEL_PATH_TINY`, or
  - `codex/models/ggml-tiny.en.bin`
- Voice notes use local transcription and will fail if these dependencies are missing.

### Storage

- `runtime/bindings.json`
- `~/.codex/remote/codexbot.pid`
- `~/.codex/remote/remote.log`
- `~/.codex/remote/codexbot-caffeinate.pid`

### Output Behavior

- The bot always sends a final Telegram message after each Codex turn.
- `/resume` and `/delete` use app-server `thread/list`; when no user-facing title is present, they fall back to the thread preview.
- If output exceeds Telegram message limits, it is split into ordered chunks and sent sequentially.
- During a running turn, the bot does not emit intermediate turn transcript items.
- At turn completion, it sends only the final assistant turn answer.
- Telegram prompts include a short final-response style instruction to keep remote replies concise.
- Prompts are serialized per Codex thread; different Codex threads can run independently.
- If a turn generates an image and app-server reports a saved local path, the bot sends that image after the final text.
- For long-running turns, Telegram `typing` action is refreshed continuously until the final reply/error is posted.

### Thread Delete Behavior

- When Codex marks a thread as pinned, remote delete is skipped and the bot tells you to unpin first.
- Chat-to-thread binding is cleared only when delete succeeds.
