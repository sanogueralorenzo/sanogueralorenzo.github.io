# Trace

Trace is a local-first memory layer for agentic coding.

The main agentic value is memory across sessions. Most coding agents start each task with only the current prompt and repository state, so they lose the reasoning behind prior changes: tradeoffs, failed attempts, constraints, reviewer feedback, and why certain code exists.

Trace attaches that missing reasoning to development history so future agents can recover context instead of rediscovering it.

In agentic workflows, this helps:

- Reduce repeated mistakes.
- Explain non-obvious code decisions.
- Make handoffs between agents cleaner.
- Let agents search prior intent, not just code.
- Turn git history into a usable memory layer.

The core value is not recording chats. The value is making development history understandable and reusable by the next agent.

## Storage Model

Trace should separate detailed recovery data from reviewable memory.

Raw conversations and checkpoints belong in a separate git ref or checkpoint store, local by default. They are useful for debugging, recovery, and deeper inspection, but they are too noisy and privacy-sensitive to live directly in the normal project tree.

Compact memories should be committed as Markdown under `.trace/`. These files should be small, redacted, and useful in code review. A memory should explain intent, decisions, affected files, validation, and remaining risks without preserving every tool call or transcript detail.

The source of truth should be commit-scoped:

```text
.trace/
  commits/
    <commit-sha>.md
```

Package-level views can be generated from those commit memories later, but they should not be the canonical store. A single change can span multiple packages, tests, configuration, and documentation, so commit-scoped memory maps more cleanly to how work actually happened.

In short:

```text
Raw conversation -> hidden checkpoint storage
Reviewable memory -> committed Markdown
Search index -> rebuildable cache
```

Trace should make the important memory visible and durable while keeping noisy transcript data separate.

## First CLI Slice

The current CLI is intentionally small and local-first:

```shell
./trace/install.sh
trace init
trace enable
trace capture --event prompt --role user --message "why this change exists"
trace record --validation "npm test"
trace show HEAD
trace log
trace search "auth retry"
trace summary main..HEAD
trace pr-body main..HEAD
```

From a checkout, the same commands can be run without installing:

```shell
node trace/bin/trace.mjs init
node trace/bin/trace.mjs enable
node trace/bin/trace.mjs capture --event prompt --role user --message "why this change exists"
node trace/bin/trace.mjs record --validation "npm test"
node trace/bin/trace.mjs show HEAD
node trace/bin/trace.mjs log
node trace/bin/trace.mjs search "auth retry"
node trace/bin/trace.mjs summary main..HEAD
node trace/bin/trace.mjs pr-body main..HEAD
```

`trace enable` installs managed `prepare-commit-msg` and `post-commit` git hook blocks. The prepare hook adds `Trace-Checkpoint` and `Trace-Session` trailers to the commit message. The post-commit hook writes a compact memory file under `.trace/commits/` and stores the raw checkpoint payload on the local `refs/trace/checkpoints` git ref.

This keeps the project tree focused on reviewable memories while raw checkpoint data stays outside the normal branch history unless someone explicitly pushes the Trace ref.

Agent integrations can start with the generic hook endpoint:

```shell
printf '{"session_id":"abc","agent":"codex","prompt":"why this task exists"}' \
  | trace hook agent prompt
```

The hook accepts JSON or plain text on stdin and records it into the local raw session store. Specific agent adapters can later translate Claude, Codex, Gemini, or other hook payloads into the same event shape without changing the memory format.
