# Trace

Trace is a small git-native memory tool for agentic coding.

Product loop:

```text
conversation + diff -> commit memory -> recall
```

Trace does one thing: every meaningful commit gets a short, redacted Markdown note that explains why the code changed, what files moved, what decisions mattered, what was validated, and what a future agent should preserve or recheck.

## Storage

Reviewable memory is committed in the project tree:

```text
.trace/
  commits/
    <commit-sha>.md
```

Raw session events stay local in the repository git common directory:

```text
<git-common-dir>/trace/sessions/<session-id>.jsonl
```

The committed Markdown is the durable source of truth. Local session events are only input material for the next commit memory.

## Commands

Set up a repository once:

```shell
trace init
trace enable
```

`trace enable` installs managed `pre-commit` and `post-commit` hooks. The pre-commit hook blocks raw `.trace/sessions/*.jsonl` style data from entering the project tree. The post-commit hook writes `.trace/commits/<sha>.md` automatically for the new commit.

Capture useful context while working:

```shell
trace capture --event prompt --role user --message "why this change exists"
trace capture --event decision --message "Keep the storage model commit-scoped"
trace capture --event validation --message "npm --prefix trace test"
```

Codex and Claude Code integrations can write the same local session stream:

```shell
cat trace/examples/codex-tool-call.json | trace hook agent --adapter codex
cat trace/examples/claude-code-user-prompt.json | trace hook agent --adapter claude-code
```

If no session exists, Trace falls back to the commit subject and diff summary so the commit still gets a useful memory note:

```shell
trace record
trace record --dry-run
trace record --session my-session --validation "npm test"
```

Retrieve memory later:

```shell
trace show HEAD
trace show HEAD --json
trace search "auth retry"
trace search --field decisions "storage"
trace recall "auth retry"
trace recall --files src/auth.ts
trace recall --json "storage"
```

Local install helpers remain available:

```shell
./trace/install.sh
./trace/install.sh --status
trace install status
```

## De-Scoped

Trace intentionally does not include Gemini or generic adapters, CI coverage gates, replay or benchmark systems, multi-agent routing, governance artifacts, PR or release generators, checkpoint sync/import/export flows, or broad adapter contract machinery.
