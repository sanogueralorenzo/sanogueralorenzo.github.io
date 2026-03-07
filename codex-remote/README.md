## Intro

**Codex Remote** is a TypeScript Telegram-to-Codex bridge for local remote operation.

## Quickstart

```shell
./scripts/install.sh
```

## Reference

### Help (`codex-remote --help`)

```text
Usage:
  ./scripts/codex-remote install
  ./scripts/codex-remote start [--plain]
  ./scripts/codex-remote stop [--plain]
  ./scripts/codex-remote status [--plain]
  ./scripts/codex-remote restart [--plain]
  ./scripts/codex-remote logs [-f|--follow]
  ./scripts/codex-remote help

Commands:
  install  Install npm dependencies in project root.
  start    Start background bot process and persist PID/log state.
  stop     Stop managed background bot process.
  status   Print managed process status.
  restart  Stop and then start managed process.
  logs     Show recent logs (or follow with -f).
  help     Print this help output.

Notes:
- Default command when omitted is: start
- start runs the bot in background and writes logs to: $HOME/.codex/remote/codex-remote.log
```

### Help Patterns

```shell
codex-remote --help
codex-remote help start
codex-remote start --help
codex-remote logs --help
```

### Required Runtime Config

- `.env` file in module root with at least:
  - `TELEGRAM_BOT_TOKEN`
  - `TELEGRAM_ALLOWED_CHAT_IDS` (optional allowlist)
  - `TELEGRAM_ADMIN_CHAT_IDS` (optional restart-admin allowlist)

### Storage

- `runtime/bindings.json`
- `~/.codex/remote/codex-remote.pid`
- `~/.codex/remote/codex-remote.log`
- `~/.codex/remote/codex-remote-caffeinate.pid`
