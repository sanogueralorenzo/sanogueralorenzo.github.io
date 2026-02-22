# gateway

Telegram to Codex bridge using `grammY` and `@openai/codex-sdk`.

## What it does

- Binds a Telegram chat to an existing Codex thread.
- Starts a fresh thread and auto-binds it.
- Forwards normal Telegram text messages into the bound Codex thread.
- Persists bindings in `data/bindings.json`.

## Requirements

- Node.js 18+
- A Telegram bot token from BotFather
- Codex CLI auth set up on this machine (`codex login`), or `CODEX_API_KEY`

## Setup

```bash
npm install
cp .env.example .env
```

Update `.env` values, then run:

```bash
npm run dev
```

Or build + run:

```bash
npm run build
npm start
```

## Telegram commands

- `/new` start a new Codex thread and bind this chat
- `/bind <thread_id>` bind to an existing Codex thread id
- `/thread` show the current bound thread id
- `/unbind` remove the binding
- `/help` show command help

## Notes

- New thread IDs are only known after the first message/turn runs. `/new` creates a pending session, and your next message initializes it.
- By default, Codex runs with:
  - `workingDirectory = CODEX_WORKING_DIRECTORY` (or current folder)
  - `skipGitRepoCheck = true`
- For production, run this as a system service (for example on your Raspberry Pi) and keep development on your Mac.
