## Intro

**Codex Remote** runs a Telegram-to-Codex bridge for remote control of local Codex workflows.

## Quickstart

```shell
./scripts/install.sh
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

### Required Config

- `.env`
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ALLOWED_CHAT_IDS` (optional)
- `TELEGRAM_ADMIN_CHAT_IDS` (optional)

### Storage

- `runtime/bindings.json`
- `~/.codex/remote/codex-remote.pid`
- `~/.codex/remote/codex-remote.log`
- `~/.codex/remote/codex-remote-caffeinate.pid`

### Draft Streaming

- Agent text snapshots are streamed through Telegram drafts.
- Each streamed snapshot uses a new draft id, so newly streamed text does not overwrite earlier draft messages.
- Snapshot sends are serialized in app-server arrival order, so the latest snapshot is sent last.
- Completed turn output is always sent as a normal Telegram message (never draft-only).
- Snapshots are stabilized before send (prefer complete lines/sentences) to reduce transient malformed formatting while streaming.

### Thread Delete Behavior

- When Codex marks a thread as pinned, remote delete is skipped and the bot tells you to unpin first.
- Chat-to-thread binding is cleared only when delete/archive succeeds.
