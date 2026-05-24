# Trace

Trace is a small Go CLI prototype for committed repository memory.

Product shape:

```text
conversation + diff -> raw checkpoint on refs/trace/checkpoints/v1 + concise .trace/commits/<sha>.md -> recall
```

## Commands

- `trace init` creates `.trace/` storage in the current Git repository.
- `trace enable` runs `init`, installs the `post-commit` Git hook, and writes hook config for Codex, Claude Code, and OpenCode.
- `trace show <commit>` prints `.trace/commits/<sha>.md`.
- `trace recall <query>` searches committed memory notes.

Trace does not install, wrap, or manage agent runtimes. Codex, Claude Code, and OpenCode must already be installed for rich conversation capture. If they are missing, `trace enable` reports that limitation and the Git commit/diff fallback remains active.

## Layout

- `.trace/sessions/<agent>/<session>.jsonl`: local raw agent hook events before commit.
- `.trace/commits/<sha>.md`: concise reviewable memory committed with the repo.
- `refs/trace/checkpoints/v1:<checkpoint>/checkpoint.json`: full redacted checkpoint record, including diff and captured sessions/transcripts.

## Hook Surface

Trace keeps the integration surface intentionally small:

- Codex project hooks in `.codex/hooks.json` for `SessionStart`, `UserPromptSubmit`, `Stop`, and `PostToolUse`.
- Claude Code project hooks in `.claude/settings.json` for `SessionStart`, `SessionEnd`, `UserPromptSubmit`, and `Stop`.
- OpenCode plugin hook events in `.opencode/plugins/trace.ts`.
- Git `post-commit` writes checkpoint data and memory notes.
