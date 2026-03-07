## Intro

**Codex Auth** is a Rust CLI for Codex auth profile lifecycle and watcher sync.

## Quickstart

```shell
./scripts/install.sh
```

## Reference

### Help (`codex-auth --help`)

```text
Manage Codex auth profiles

Usage: codex-auth [OPTIONS] <COMMAND>

Commands:
  save     Save a profile from current auth.json or explicit --path
  use      Apply a saved profile or explicit --path to auth.json
  list     List saved profiles
  current  Print current profile and auth metadata
  remove   Delete a saved profile
  watch    Manage auth sync watcher (start|stop|status|run)
  help     Print this message or the help of the given subcommand(s)

Options:
      --home <dir>
  -h, --help        Print help
```

### Help (`codex-auth watch --help`)

```text
Manage auth sync watcher (start|stop|status|run)

Usage: codex-auth watch [OPTIONS] <COMMAND>

Commands:
  start   Start auth sync watcher in background
  stop    Stop background auth sync watcher
  status  Print watcher status
  run     Run watcher loop in foreground
  help    Print this message or the help of the given subcommand(s)

Options:
      --home <dir>
  -h, --help        Print help
```

### Help Patterns

```shell
codex-auth --help
codex-auth -h
codex-auth help watch
codex-auth watch --help
codex-auth watch start --help
```

### Storage

- `~/.codex/auth.json`
- `~/.codex/auth.json.lock`
- `~/.codex/auth/profiles/*.json`
- `~/.codex/auth/active-account-id`
- `~/.codex/auth/codex-auth-watch.pid`
- `~/.codex/auth/codex-auth-watch.log`
