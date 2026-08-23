# Trace

Trace stores AI coding conversations in hidden Git refs and links them to
commits without changing normal branches or commit messages.

```text
session    = one complete conversation
checkpoint = the part of that session linked to one commit
```

## Install

Requires Git and Go 1.26 or newer.

```sh
go install .
```

macOS ships an unrelated `/usr/bin/trace`. Put Go's binary directory first in
`PATH` and check that `trace help` shows this CLI.

## Enable capture

Run once in a Git repository:

```sh
trace enable
```

This installs a managed `post-commit` hook and configures Codex, Claude Code,
OpenCode, Pi, and Oh My Pi capture. Existing Git hook content is preserved.
Live state stays outside the worktree in Git's common directory and is isolated
per worktree.

Every agent adapter sends the same lifecycle events through `trace ingest`:
`session-start`, `turn-start`, `turn-end`, and `session-end`. Agent-specific
code is limited to installing hooks and making its transcript readable.

## Read sessions

```sh
trace sessions
trace session <session-id>
trace show <commit>
```

- `sessions` lists complete sessions.
- `session` shows one conversation and all of its checkpoints.
- `show` shows only the conversation range linked to a commit. Git revisions
  such as `HEAD`, branch names, and commit SHAs work.

Add `--json` to any read command for machine-readable output. Records include a
`schema_version`.

## Push and fetch

Normal Git pushes and clones do not include custom refs. Push Trace history
explicitly:

```sh
trace push origin
```

After a fresh clone, fetch it and inspect the stored conversations:

```sh
trace fetch origin
trace sessions
```

`push` and `fetch` transfer both the session refs and commit-note links. They
fail on conflicting histories instead of silently overwriting either side.

## Other AI tools

Any tool can send a JSON event on standard input:

```sh
printf '%s\n' '{
  "session_id": "full-stable-id",
  "model": "model-name",
  "prompt": "Add validation",
  "response": "Validation added"
}' | trace ingest my-tool turn-start
```

`session_id` is required. Payloads may contain ordered `messages`, a
`prompt`/`response` pair, a `transcript_path`, and model metadata. Reusing the
same source and session ID extends that session.

## Stored data

- `refs/trace/sessions/v4/<shard>/<key>`: one self-contained record per session
- `refs/notes/trace`: commit-to-session pointers
- `$GIT_COMMON_DIR/trace/worktrees/<key>/`: private live capture state

A session record contains its stable ID, source, branch, timestamps, models,
transcript availability, redacted messages/events, and checkpoints. Each
checkpoint contains commit metadata and the exact message/event range assigned
to that commit.

Durable records redact common secret patterns. Raw live events are not redacted,
so keep the common-directory `trace/` data private.

Trace intentionally has no code snapshots, rewind system, cloud service, or
token analytics.
