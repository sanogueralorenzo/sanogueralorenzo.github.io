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
codex-sessions watch thread-titles --help
```

### Commands (`codex-sessions --help`)

```text
list                   List sessions with optional filters/pagination
titles                 List resolved conversation titles by session id
generate-thread-title  Generate and persist a session title from first user input
show                   Show one session by id or unique id prefix
message                Print latest assistant message for a session
delete                 Archive by default, or hard delete sessions with --hard
archive                Move sessions to archived storage
unarchive              Move sessions from archived storage to active storage
merge                  Summarize one session into another and delete merged session
prune                  Prune old active sessions once
watch                  Watchers for session maintenance flows
help                   Print help
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
