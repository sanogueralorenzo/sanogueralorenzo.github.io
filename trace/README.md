# Trace

Trace keeps local history for AI coding sessions and connects that history to
Git commits.

```text
AI session -> hidden Git ref
Git commit -> session + message/event range
```

It stores complete redacted sessions, not generated summaries or copied diffs.
Session data stays off normal branches, and nothing is uploaded unless you
explicitly push the Trace refs.

## Install

Requires Git and Go 1.26 or newer.

```sh
go install .
```

macOS already ships an unrelated `/usr/bin/trace`. Put Go's binary directory
first in `PATH`, then verify that `trace help` shows this CLI.

## Start tracing

Run once inside a Git repository:

```sh
trace enable
```

Trace installs a managed `post-commit` block without removing existing hook
content and configures its Codex, Claude Code, and OpenCode adapters. Sessions
are saved locally as events arrive. Each commit is automatically linked to the
new part of every active session.

Adapter setup may create or update `.codex/`, `.claude/`, and `.opencode/`
project files. Live session state is kept inside Git's common directory, so it
stays out of the worktree. It is scoped per worktree to prevent a commit in one
worktree from claiming another worktree's active session.

## CLI

```sh
trace sessions
trace session <session-id>
trace show <commit>
```

- `trace sessions` lists stored sessions, newest first.
- `trace session <session-id>` shows the complete session, its metadata, and all
  linked commits.
- `trace show <commit>` shows only the part of each session linked to that Git
  revision. `HEAD`, branches, and commit SHAs work.
- `trace init` creates storage without installing hooks.

Add `--json` to the three read commands for stable, machine-readable output:

```sh
trace sessions --json
trace session <session-id> --json
trace show HEAD --json
```

JSON records include `schema_version` so agents and skills can evolve with the
format.

## Other AI tools

Any tool can write a session event as JSON on standard input:

```sh
printf '%s\n' '{
  "session_id": "full-stable-id",
  "model": "model-name",
  "messages": [
    {"role": "user", "text": "Add validation"},
    {"role": "assistant", "text": "Validation added"}
  ]
}' | trace ingest my-tool snapshot
```

`session_id` is required. A payload may provide:

- `messages`: ordered user/assistant messages
- `prompt` and `response` or `output`: one exchange
- `transcript_path`: a JSON or JSONL transcript to read
- `model`, `model_id`, or `modelID`: model metadata

The source and event names are free-form. In the example they are `my-tool` and
`snapshot`. Reusing the same session ID appends to that session.

## Session metadata

Each durable session records the context needed for later analysis:

- stable session ID, source, and schema version
- repository name, sanitized origin URL, and current branch
- start and update times
- models, message count, event count, and event kinds
- transcript status (`captured`, `not_provided`, or `unavailable`) and a reason
  when a supplied transcript cannot be read
- complete redacted messages and source events
- linked commit SHA, subject, branch, time, changed files, and message/event range

This makes `trace session <id> --json` suitable as input when reviewing agent
behavior or improving prompts, agents, and skills.

## Local storage

- `refs/trace/sessions/v3/<shard>/<key>`: one durable, self-contained record per
  session
- `refs/notes/trace`: commit-to-session pointers
- `$GIT_COMMON_DIR/trace/worktrees/<key>/sessions/`: raw hook events
- `$GIT_COMMON_DIR/trace/worktrees/<key>/state.json`: commit cursors

Durable records redact common secret patterns. Raw hook events are not redacted
at capture time, so keep the common-directory `trace/` data private. Independent
session refs avoid a shared write bottleneck, and ref updates fail instead of
silently overwriting a concurrent change.

Trace refs are local by default and are not included in a normal push. Sharing
is optional:

```sh
git push origin 'refs/trace/sessions/v3/*:refs/trace/sessions/v3/*' refs/notes/trace
```

## Design scope

Trace borrows the durable, self-contained records and independent-ref approach
described by [Entire's session/checkpoint design](https://github.com/entireio/cli/blob/main/docs/architecture/sessions-and-checkpoints.md)
and [ref backend](https://github.com/entireio/cli/blob/main/docs/architecture/ref-checkpoint-backend.md).
It deliberately remains session-first: no shadow code snapshots, checkpoint
duplication, commit trailers, rewind/resume system, cloud queue, or token
analytics.
