## Intro

**Codex Remote** is a TypeScript Telegram-to-Codex bridge for local remote operation.

## Quickstart

### Install and start

```shell
../codex-sessions/scripts/install.sh
./scripts/install.sh
cp .env.example .env
codex-remote install
codex-remote start
```

## Reference

- Required env:

```env
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_CHAT_IDS=...
TELEGRAM_ADMIN_CHAT_IDS=...
```

- Common commands:

```shell
codex-remote start
codex-remote status
codex-remote stop
codex-remote restart
codex-remote logs -f
```

- Optional voice-note transcription requires `ffmpeg` + `whisper-cli` and `WHISPER_MODEL_PATH_TINY`.
- Runtime binding store: `runtime/bindings.json`.
