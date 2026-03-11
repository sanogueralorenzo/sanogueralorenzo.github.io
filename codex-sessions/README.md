## Intro

**Codex Sessions** manages local Codex thread/session lifecycle, titles, merge, and cleanup.

## Quickstart

```shell
./scripts/install.sh
```

## Reference

### CLI

```shell
codex-sessions --help
codex-sessions auto-remove --help
codex-sessions watch thread-titles --help
codex-sessions watch auto-remove --help
```

### Commands (`codex-sessions --help`)

```text
list                   List sessions with optional filters/pagination
titles                 List resolved conversation titles by session id
generate-thread-title  Generate and persist a session title from first user input
show                   Show one session by id or unique id prefix
message                Print latest assistant message for a session
delete                 Permanently delete one or more sessions
archive                Move sessions to archived storage
unarchive              Move sessions from archived storage to active storage
merge                  Summarize one session into another and delete merged session
auto-remove            Auto-remove old active sessions once
watch                  Watchers for session maintenance flows
help                   Print help
```

### Commands (`codex-sessions watch --help`)

```text
auto-remove    Run auto-remove repeatedly on an interval
thread-titles  Manage thread-title watcher (start|stop|status|run)
help           Print help
```

### Commands (`codex-sessions watch thread-titles --help`)

```text
start    Start title watcher in background
stop     Stop background title watcher
status   Print title watcher status
run      Run title watcher loop in foreground
help     Print help
```

### Storage

- `~/.codex/state_*.sqlite`
- `~/.codex/sessions/**`
- `~/.codex/archived_sessions/**`
- `~/.codex/.codex-global-state.json`
- `~/.codex/.locks/title-write.lock`
- `~/.codex/sessions/codex-sessions-watch-thread-titles.pid`
- `~/.codex/sessions/codex-sessions-watch-thread-titles.log`

### Pinned Thread Protection

- `delete` and `auto-remove` skip thread IDs listed in `~/.codex/.codex-global-state.json` under `pinned-thread-ids`.
- To delete a pinned thread, unpin it first in Codex so the ID is removed from `pinned-thread-ids`.

### Auto-Remove Mode

- `auto-remove` requires `--mode` on every run:
  - `--mode archive` moves matching sessions to `archived_sessions`.
  - `--mode delete` permanently deletes matching sessions.
- The same applies to `watch auto-remove`.

### Delete/Auto-Remove Result Schema

- `delete` / `archive` / `unarchive` item results now use typed fields:
  - `status`: `succeeded | skipped | failed`
  - `reason`: `completed | dry_run | pinned | error`
  - `message`: optional detail text
- Batch result objects use `operation` as the top-level field.
- `auto-remove` results use top-level `mode` (`archive | delete`).
