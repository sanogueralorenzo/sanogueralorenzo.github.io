# codex-sessions

`codex-sessions` is a Rust CLI to inspect and manage local Codex sessions.

It is designed to be shared by other tools (for example menu bar integrations and `codex-remote`) so session lifecycle behavior lives in one place.

## Build

```bash
cd /Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/codex-sessions
cargo build
```

## Install

```bash
cd /Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/codex-sessions
./scripts/install.sh
```

Installs to npm global `bin` (`$(npm config get prefix)/bin`).

## Commands

```bash
# List active sessions (defaults to current working directory)
codex-sessions list

# List across all folders
codex-sessions list --all

# List archived sessions
codex-sessions list --archived --all

# List with filters + pagination cursor
codex-sessions list --all --source-kind vscode --sort-by updated_at --limit 20
codex-sessions list --all --cursor <last-id-from-previous-page>

# Search by title/id/cwd
codex-sessions list --all --search "jira"

# List saved desktop thread titles
codex-sessions titles --json

# Show one session by full id or unique prefix
codex-sessions show 019cc5d1 --json

# Read latest assistant message from a session
codex-sessions message 019cc5d1 --json

# Remove from active history (default: archive)
codex-sessions delete 019cc5d1

# Hard delete (file + thread row)
codex-sessions delete 019cc5d1 --hard

# Explicit archive/unarchive
codex-sessions archive 019cc5d1
codex-sessions unarchive 019cc5d1

# Prune old active sessions (default: archive)
codex-sessions prune --older-than-days 7

# Hard-delete while pruning
codex-sessions prune --older-than-days 7 --hard

# Dry-run prune
codex-sessions prune --older-than-days 7 --dry-run --json

# Keep a terminal running and prune on an interval
codex-sessions watch --older-than-days 7 --interval-minutes 60

# One-shot watch cycle (useful for scheduled jobs)
codex-sessions watch --older-than-days 7 --interval-minutes 60 --once
```

## Notes

- Default Codex home is `~/.codex`.
- Use `--home /path/to/codex-home` to point to another location.
- Session metadata is read from Codex state DB when available; file metadata is used as fallback.
- `delete` archives by default; pass `--hard` for permanent removal.

## Project structure

- `src/adapters`: low-level filesystem/state operations.
- `src/services`: session filtering/pruning business logic.
- `src/shared`: shared models and output-format helpers.
- `src/commands.rs`: CLI command handlers and output rendering.
- `src/cli.rs`: clap command/argument definitions.
