# Trace

Trace links each Git commit to the agent conversation that produced it.

```text
commit -> full session_id + conversation range
```

A session can span multiple commits, and a commit can link to multiple
sessions. Trace stores the complete redacted session once, then uses Git notes
to record which messages and events belong to each commit.

## Requirements

- Git
- Go 1.26 or newer
- Codex, Claude Code, or OpenCode for conversation capture

Trace does not install or manage agent runtimes. A commit made without captured
session activity remains unlinked.

## Install

From this directory:

```sh
go install .
```

Make sure Go's binary directory is in `PATH`. macOS already ships a different
`/usr/bin/trace`, so the Go binary directory must appear first. Verify with:

```sh
command -v trace
trace
```

The second command should print:

```text
usage: trace <init|enable|hooks|show|session>
```

## Quick start

Inside the Git repository you want to trace:

```sh
trace enable
```

Then work and commit normally. To inspect the conversation linked to the latest
commit:

```sh
trace show HEAD
```

The output includes the full session ID and only the conversation range linked
to that commit. To see the complete session and every commit it produced:

```sh
trace session <session-id>
```

## Commands

- `trace enable` initializes Trace and installs the Git and agent hooks. This is
  the recommended setup command.
- `trace init` creates `.trace/` storage without installing hooks.
- `trace show <commit>` shows the conversation range for any Git revision, such
  as `HEAD`, a branch, or a commit SHA.
- `trace session <session-id>` shows the complete session and all linked
  commits. Use the full ID printed by `trace show`.
- `trace hooks ...` is an internal entry point used by installed integrations.

`trace enable` writes project hook configuration for Codex, Claude Code, and
OpenCode, and installs `.git/hooks/post-commit`. Review generated repository
files before committing them.

## Storage

Local working data is ignored by Git:

- `.trace/sessions/<agent>/<session>.jsonl`: raw hook events
- `.trace/tmp/`: temporary transcript exports
- `.trace/state.json`: per-session commit cursors

Durable history lives outside the current branch:

- `refs/trace/sessions/v1`: complete redacted session records
- `refs/notes/trace`: commit links and message/event ranges

Normal pushes and fetches do not include these refs. To share Trace history:

```sh
git push origin refs/trace/sessions/v1 refs/notes/trace
```

Fetch it with:

```sh
git fetch origin \
  refs/trace/sessions/v1:refs/trace/sessions/v1 \
  refs/notes/trace:refs/notes/trace
```

Trace redacts common secret patterns before writing durable records. Raw local
hook events are not redacted at capture time, so keep `.trace/sessions/`
private.
