## Intro

**Codex Auth** manages local Codex auth profiles and sync watcher state.

## Quickstart

```shell
./scripts/install.sh
```

## Reference

### CLI

```shell
codex-auth --help
codex-auth watch --help
```

### Commands (`codex-auth --help`)

```text
save     Save a profile from current auth.json or explicit --path
use      Apply a saved profile or explicit --path to auth.json
list     List saved profiles
current  Print current profile and auth metadata
remove   Delete a saved profile
watch    Manage auth sync watcher (start|stop|status|run)
help     Print help
```

### Runtime Behavior

- `use` only manages the Codex macOS app lifecycle (it does not terminate terminal sessions).
- If the Codex macOS app is running when `use` starts, `codex-auth`:
  1. closes the app,
  2. waits 3 seconds,
  3. applies the new profile/auth file,
  4. waits 3 seconds,
  5. reopens the app.
- If the Codex macOS app is not running, `use` applies the profile/auth file and asks you to restart Codex manually.

### Commands (`codex-auth watch --help`)

```text
start    Start auth sync watcher in background
stop     Stop background auth sync watcher
status   Print watcher status
run      Run watcher loop in foreground
help     Print help
```

### Storage

- `~/.codex/auth.json`
- `~/.codex/auth/profiles/*.json`
- `~/.codex/auth/active-account-id`
- `~/.codex/auth/codex-auth-watch.pid`
- `~/.codex/auth/codex-auth-watch.log`
