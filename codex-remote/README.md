## Intro

**Codex Remote** runs a Telegram-to-Codex bridge for remote control of local Codex workflows.

## Quickstart

```shell
./scripts/install.sh
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
- Each turn reuses a single draft id, so draft updates animate in place.
- Snapshot sends are serialized in app-server arrival order, so the latest snapshot is sent last.
- Completed turn output is always sent as a normal Telegram message (never draft-only).
- After final output is sent, the streamer performs a best-effort draft clear (`sendMessageDraft` empty-text, then invisible-char fallback for strict validators).
- Snapshots are stabilized before send (prefer paragraph/line/sentence boundaries and closed code fences) and initial preview waits for a minimum stable chunk to reduce transient malformed formatting.
- Draft previews cap at 800 chars for readability; final output still sends complete text via normal Telegram messages.
- Draft streaming internals follow OpenClaw-aligned file layout:
  `draft-chunking.ts`, `draft-stream-loop.ts`, `draft-stream-controls.ts`, `draft-stream.ts`.

### Thread Delete Behavior

- When Codex marks a thread as pinned, remote delete is skipped and the bot tells you to unpin first.
- Chat-to-thread binding is cleared only when delete/archive succeeds.
