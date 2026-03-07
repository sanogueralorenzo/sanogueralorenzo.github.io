## Intro

**Codex Auth** is a local profile manager for Codex auth accounts.

## Quickstart

```shell
./scripts/install.sh
```

## Reference

### Help (`codex-auth help`)

```text
Usage:
  codex-auth [--home <dir>] save <profile> [--path <auth.json> | --from-current]
  codex-auth [--home <dir>] add <profile> [--path <auth.json> | --from-current]
  codex-auth [--home <dir>] use <profile>
  codex-auth [--home <dir>] use --path <auth.json>
  codex-auth [--home <dir>] list [--plain]
  codex-auth [--home <dir>] current [--plain]
  codex-auth [--home <dir>] remove <profile>
  codex-auth [--home <dir>] watch <start|stop|status|run>
  codex-auth [--home <dir>] help

Commands:
  save/add   Save a profile from current auth.json or explicit --path
  use        Apply a saved profile or explicit --path to auth.json
  list       List saved profiles
  current    Print current profile and auth metadata
  remove     Delete a saved profile
  watch      Manage auth sync watcher (start|stop|status|run)
  help       Print this help output

Examples:
  codex-auth save personal
  codex-auth save work --path ~/secrets/work-auth.json
  codex-auth use work
  codex-auth remove personal
  codex-auth watch start
```

### Storage

- `~/.codex/auth.json`
- `~/.codex/auth.json.lock`
- `~/.codex/auth/profiles/*.json`
- `~/.codex/auth/active-account-id`
- `~/.codex/auth/codex-auth-watch.pid`
- `~/.codex/auth/codex-auth-watch.log`
