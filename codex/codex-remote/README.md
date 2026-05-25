## Intro

**Codex Remote** runs a Telegram-to-Codex bridge for remote control of local Codex workflows.

## Quickstart

```shell
../codex-core/scripts/install.sh
./scripts/install.sh
npm install
npm run generate:app-server-types
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
- `codex` on `PATH` for app-server transport
- `codex-core` on `PATH` for thread/session operations (installed by root `./install.sh` or `../codex-core/scripts/install.sh`)
- `CODEX_BIN` (optional app-server CLI override; defaults to `codex`)
- `CODEX_CORE_BIN` (optional session CLI override; defaults to `codex-core`)
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ALLOWED_CHAT_IDS` (optional)
- `PRECEDENT_ENABLED=1` (optional) injects replay-verified Precedent context into bound Codex turns.
- `PRECEDENT_STATE_DIR` (optional, defaults to `.precedent`)
- `PRECEDENT_CONTEXT_TIMEOUT_MS` (optional, defaults to `2500`) caps before-turn context and repair prompt calls.
- `PRECEDENT_HOOK_TIMEOUT_MS` (optional, defaults to `1500`) caps advisory validation, diff, retry receipt, and outcome hooks.
- Node dependencies installed in `codex-remote` (`npm install`)

### App Server Protocol Types

- `npm run generate:app-server-types` refreshes generated TypeScript protocol types from `codex app-server generate-ts --experimental`.
- `npm run typecheck` first runs `npm run check:app-server-types` and fails when committed generated types are stale.

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
- `~/.codex/remote/remote.log`
- `~/.codex/remote/codex-remote-caffeinate.pid`

### Output Behavior

- The bot always sends a final Telegram message after each Codex turn.
- Startup runs `codex-core sessions watch thread-titles start --home <CODEX_HOME>` so `/resume` and `/delete` can show generated thread titles when Codex initially stores the first prompt as the title.
- If output exceeds Telegram message limits, it is split into ordered chunks and sent sequentially.
- During a running turn, the bot does not emit intermediate turn transcript items.
- At turn completion, it sends only the final assistant turn answer.
- Prompts are serialized per Codex thread; different Codex threads can run independently.
- If a turn generates an image and app-server reports a saved local path, the bot sends that image after the final text.
- For long-running turns, Telegram `typing` action is refreshed continuously until the final reply/error is posted.
- When `PRECEDENT_ENABLED=1`, Codex Remote calls Precedent with the bound Codex thread id before each normal turn. Only `contextBlock` is prepended to the prompt; `candidateHints` and `promotionTrials` remain telemetry and are never injected as instructions.
- If Precedent records a repairable failure, Codex Remote can prepend one `repairBlock` to a hidden same-thread repair continuation before replying, or to the next normal prompt when the failure was already present before the turn. It records the retry receipt after the repaired turn.
- Precedent calls are bounded by timeout and fail open: a hung or failing Precedent process cannot block a Telegram turn.

### Thread Delete Behavior

- When Codex marks a thread as pinned, remote delete is skipped and the bot tells you to unpin first.
- Chat-to-thread binding is cleared only when delete succeeds.
