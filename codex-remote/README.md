## Intro

**Codex Remote** runs a Telegram-to-Codex bridge for remote control of local Codex workflows.

## Quickstart

```shell
./scripts/install.sh
npm run typecheck
npm run test
```

Install dependency:

```shell
../codex-app-server/scripts/install.sh
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
- `codex-app-server` on `PATH` (installed by root `./install.sh` or `../codex-app-server/scripts/install.sh`)
- `codex-app-server` command surfaces used by remote:
  - `rpc` (for app-server transport)
  - `sessions` (for thread/session operations)
- `CODEX_APP_SERVER_BIN` (optional override path/name; defaults to `codex-app-server`)
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ALLOWED_CHAT_IDS` (optional)

### Storage

- `runtime/bindings.json`
- `~/.codex/remote/codex-remote.pid`
- `~/.codex/remote/codex-remote.log`
- `~/.codex/remote/codex-remote-caffeinate.pid`

### Output Behavior

- The bot always sends a final Telegram message after each Codex turn.
- If output exceeds Telegram message limits, it is split into ordered chunks and sent sequentially.
- During a running turn, the bot emits only the first completed assistant message item (`agentMessage`) and suppresses command/tool/reasoning/plan progress noise.
- At turn completion, it sends the final assistant turn answer. If that final answer matches the first emitted message exactly, it is not sent twice.
- For long-running turns, Telegram `typing` action is refreshed continuously until the final reply/error is posted.

### Thread Delete Behavior

- When Codex marks a thread as pinned, remote delete is skipped and the bot tells you to unpin first.
- Chat-to-thread binding is cleared only when delete/archive succeeds.
