## Intro

**Codex Sessions** is a Rust CLI for local Codex session inspection and lifecycle management.

## Quickstart

### Install and run

```shell
./scripts/install.sh
codex-sessions list --all
```

## Reference

- Core commands:

```shell
codex-sessions show <SESSION_ID> --json
codex-sessions message <SESSION_ID> --json
codex-sessions archive <SESSION_ID>
codex-sessions delete <SESSION_ID>
codex-sessions prune --older-than-days 7 --dry-run --json
```

- Defaults:
  - Codex home: `~/.codex`
  - `delete` archives by default; use `--hard` for permanent delete.
