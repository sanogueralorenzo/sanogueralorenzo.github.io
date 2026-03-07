## Intro

**Codex Sessions** is a Rust CLI for local Codex session inspection and lifecycle management.

## Quickstart

```shell
./scripts/install.sh
```

## Reference

### Help (`codex-sessions --help`)

```text
Manage local Codex session files

Usage: codex-sessions <COMMAND>

Commands:
  list       List sessions with optional filters/pagination
  titles     List desktop thread-title mappings
  show       Show one session by id or unique id prefix
  message    Print latest assistant message for a session
  delete     Archive by default, or hard delete with --hard
  archive    Move one session to archived storage
  unarchive  Move one session from archived storage to active storage
  merge      Summarize one session into another and delete the merged session
  prune      Prune old active sessions once
  watch      Run prune repeatedly on an interval
  help       Print this message or the help of the given subcommand(s)

Options:
  -h, --help  Print help
```

### List Ordering

- `list --folders` orders sessions by folder, then by `last_updated_at` descending inside each folder.
- JSON list output includes `folder` for each entry.

### Merge Behavior

- `merge --target <source> --merge <merger>` runs a two-pass context transfer:
  1) resume merger session to generate compact transfer summary,
  2) resume source session with that summary,
  then hard-delete the merger session on success.

### Storage

- `~/.codex/state_*.sqlite`
- `~/.codex/sessions/**`
- `~/.codex/archived_sessions/**`
- `~/.codex/.codex-global-state.json`
