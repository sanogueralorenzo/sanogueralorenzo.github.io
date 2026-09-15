## Intro

**Codex Bot** runs a Telegram-to-Codex bridge for controlling local Codex workflows.

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

### Telegram Topics

Use the bot in a Telegram supergroup with Topics enabled. Each topic is one permanent Codex session, so messages, approvals, questions, voice notes, and replies stay together. The bot needs permission to manage topics so it can create, rename, and close them.

- `/new [title]` creates a topic. The first message in that topic starts its Codex session.
- `/archive` archives the topic's Codex session and closes the Telegram topic.
- `/rename <title>` renames both the Telegram topic and its Codex session.
- `/goal` shows the current goal for the topic's Codex session.
- `/goal <objective>` sets the topic's goal and marks it active.
- `/goal pause`, `/goal resume`, and `/goal clear` update or clear the topic's goal.
- `/start` and `/help` show the command list. Voice notes are supported inside topics.

Send prompts inside a topic. Messages in Telegram's General area are not sent to Codex; use `/new [title]` to create a topic first.

### Required Config

- `.env`
- `codex` on `PATH` for app-server transport and thread/session operations
- `CODEX_BIN` (optional Codex CLI override; defaults to `codex`)
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ALLOWED_CHAT_IDS` (required; the bot refuses to start without it)
- Node dependencies installed in `codexbot` (`npm install`)

### App Server Protocol Types

- `npm run generate:app-server-types` refreshes generated TypeScript protocol types from `codex app-server generate-ts --experimental`.
- `npm run typecheck` first runs `npm run check:app-server-types` and fails when committed generated types are stale.

### Voice Note Requirements

- `whisper-cli` on `PATH`
- `ffmpeg` on `PATH`
- Whisper model file at either:
  - `WHISPER_MODEL_PATH_TINY`, or
  - `codexbot/models/ggml-tiny.en.bin`
- Voice notes use local transcription and will fail if these dependencies are missing.

### Storage

- `runtime/topics.json` (Telegram topic to Codex session mappings)
- `~/.codex/codexbot/codexbot.pid`
- `~/.codex/codexbot/codexbot.log`
- `~/.codex/codexbot/codexbot-caffeinate.pid`

### Output Behavior

- The bot always sends a final Telegram message after each Codex turn.
- If output exceeds Telegram message limits, it is split into ordered chunks and sent sequentially.
- During a running turn, the bot does not emit intermediate turn transcript items.
- When Codex requests user input, the bot presents the question in Telegram and returns the answer to the active turn.
- At turn completion, it sends only the final assistant turn answer.
- Telegram prompts include a short final-response style instruction to keep remote replies concise.
- Prompts are serialized per Telegram topic; different topics can run independently.
- If a turn generates an image and app-server reports a saved local path, the bot sends that image after the final text.
- For long-running turns, Telegram `typing` action is refreshed continuously until the final reply/error is posted.

### Topic Archive Behavior

- Archiving a topic archives its Codex session, closes the Telegram topic, and removes its local mapping.
- A new topic always gets its own Codex session on the first prompt.
