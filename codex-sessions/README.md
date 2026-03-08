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
  titles     List resolved conversation titles by session id
  generate-thread-title  Generate and persist a session title from first user input
  show       Show one session by id or unique id prefix
  message    Print latest assistant message for a session
  delete     Archive by default, or hard delete sessions with --hard
  archive    Move one or more sessions to archived storage
  unarchive  Move one or more sessions from archived storage to active storage
  merge      Summarize one session into another and delete the merged session
  prune      Prune old active sessions once
  watch      Watchers for session maintenance flows
  help       Print this message or the help of the given subcommand(s)

Options:
  -h, --help  Print help
```

### List Ordering

- `list --folders` orders sessions by folder, then by `last_updated_at` descending inside each folder.
- JSON list output includes `folder` for each entry.
- Session titles in list/titles output prefer `~/.codex/session_index.jsonl` (`thread_name`), then fall back to `state_*.sqlite` title (and global-state fallback for file-scan mode).

### Merge Behavior

- `merge --target <target> --merge <merger>` runs a two-pass context transfer:
  1) resume merger session to generate compact transfer summary,
  2) resume target session with that summary,
  then hard-delete the merger session on success.
- Merger summary prompt enforces deterministic markdown headings:
  - `## Decisions`
  - `## Constraints`
  - `## Preferences`
  - `## Resolved Facts`
  - `## Relevant Open Questions`
- Merge prompts avoid actionable instructions, include conflict-handling guidance, and target apply step responds with exactly `Thread merged`.

### Delete Behavior

- Hard delete removes:
  - session file
  - `threads` row in `state_*.sqlite` (when present)
  - matching title key in `~/.codex/.codex-global-state.json` (`thread-titles.titles.<session_id>`) when present
- `delete --hard <ids...>` resolves all ids/prefixes once, then processes them in one CLI invocation.
- `delete` also supports selector mode (no IDs):
  - `--all`
  - `--older-than-days <n>`
  - `--folder <folder_label>`
  - `--search <substring>`
  - destructive selector mode requires `--yes` (or use `--dry-run`)
- selector example:
  - `codex-sessions delete --hard --older-than-days 7 --all --yes`
- batch JSON output includes: `processed`, `succeeded`, `failed`, `skipped`.
- `prune --hard` batches stale-session row deletes in one DB transaction and rewrites global titles once per prune run.

### Title Generation

- `generate-thread-title <id>` generates a title using the same Codex desktop rules:
  - model: `gpt-5.1-codex-mini`
  - effort: `low`
  - prompt input truncated to 2000 chars
  - post-normalization strips `title:` prefix, trims quotes/spacing, strips trailing `.?!`, enforces 18-36 chars
- command requires an existing first user prompt and at least one assistant response in the target session.
- title writes are applied to:
  - `threads.title` in `state_*.sqlite` (when present)
  - `thread-titles.titles.<id>` in `~/.codex/.codex-global-state.json`
  - `thread_name` (and `title`) in `~/.codex/session_index.jsonl`
- write concurrency for title persistence uses advisory `flock` at `~/.codex/.locks/title-write.lock`:
  - waits up to 10s to acquire lock, then fails with timeout error
  - lock scope covers only JSON file persistence (model generation runs outside lock)
  - JSON writes use atomic `tmp + fsync + rename` while lock is held

### Title Watcher

- `watch thread-titles start` starts a single background watcher process.
- `watch thread-titles stop` stops that background process.
- `watch thread-titles status` prints running/stopped state and PID when running.
- `watch thread-titles run` runs foreground polling loop; `watch thread-titles run --once` runs one scan.
- Poll interval is fixed at 10 seconds.
- Scan source is latest `state_*.sqlite`, selecting threads with empty `threads.title`.
- Each candidate is re-checked before persist; non-empty titles are skipped.

### Storage

- `~/.codex/state_*.sqlite`
- `~/.codex/sessions/**`
- `~/.codex/archived_sessions/**`
- `~/.codex/.codex-global-state.json`
- `~/.codex/.locks/title-write.lock`
- `~/.codex/sessions/codex-sessions-watch-thread-titles.pid`
- `~/.codex/sessions/codex-sessions-watch-thread-titles.log`
- `~/.codex/sessions/codex-sessions-watch-thread-titles.state.json`
