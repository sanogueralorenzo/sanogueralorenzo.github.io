# Trace

Trace connects each Git commit to the agent conversation that produced it.

One session can span many commits, and one commit can include work from many
sessions:

```text
commit -> session_id + conversation range
```

Trace stores each full, redacted session once. A Git note on each commit records
the exact message and event range associated with that commit. The full
`session_id` stays visible in both views.

## Install

Build or install the CLI from this directory:

```sh
go install .
```

Then run Trace inside any Git repository you want to remember:

```sh
trace enable
```

`trace enable` is the main setup command. It initializes `.trace/`, installs the
Git `post-commit` hook, and wires supported agent hooks where possible.

Trace does not install, wrap, or manage agent runtimes. Codex, Claude Code, and
OpenCode must already be installed for their sessions to be captured. Commits
without a captured session remain unlinked.

OpenCode transcript export uses the installed `opencode` CLI and caches the
export under `.trace/tmp/opencode/`.

## Usage

1. Run `trace enable` once in a repository.
2. Work normally with Codex, Claude Code, or OpenCode.
3. Commit normally with `git commit`.
4. Inspect the conversation for a commit or its complete session:

```sh
trace show HEAD
trace session 019d2a5f-5e87-7a31-9f8b-4c29c7de1024
```

`trace show` prints only the part of each session linked to that commit. `trace
session` prints the complete conversation and every linked commit.

## Command Reference

- `trace init` creates `.trace/` storage in the current Git repository.
- `trace enable` runs `init`, installs the `post-commit` Git hook, and writes hook config for Codex, Claude Code, and OpenCode.
- `trace show <commit>` prints the commit-scoped conversation.
- `trace session <session-id>` prints the full session and its linked commits.

## Layout

- `.trace/sessions/<agent>/<session>.jsonl`: local raw agent hook events before commit.
- `.trace/tmp/opencode/<session>.json`: temporary OpenCode transcript export cache.
- `.trace/state.json`: local cursors that separate one session across commits.
- `refs/trace/sessions/v1`: durable full-session records.
- `refs/notes/trace`: commit-to-session links and message/event ranges.

The two refs are separate from the current branch. Push them explicitly when
you want to share Trace history:

```sh
git push origin refs/trace/sessions/v1 refs/notes/trace
```

## Hook Surface

Trace keeps the integration surface intentionally small:

- Codex project hooks in `.codex/hooks.json` for `SessionStart`, `UserPromptSubmit`, `Stop`, and `PostToolUse`.
- Claude Code project hooks in `.claude/settings.json` for `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Stop`, and Task `PreToolUse`/`PostToolUse`.
- OpenCode plugin hook events in `.opencode/plugins/trace.ts`.
- Git `post-commit` links the new commit to captured session ranges.
