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
