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
./trace/install.sh --update
./trace/install.sh --uninstall
trace init
trace enable
trace agent add codex
trace agent add claude-code
trace agent add gemini
trace capture --event prompt --role user --message "why this change exists"
trace record --validation "npm test"
trace show HEAD
trace log
trace index
trace search "auth retry"
trace search --field decisions "retry"
trace search --field files "auth"
trace summary main..HEAD
trace pr-body main..HEAD
trace release-notes v1.0.0..HEAD
trace checkpoint list
trace checkpoint verify
trace checkpoint push origin --dry-run
trace checkpoint cleanup --sessions-before-days 14
trace redact add codename 'PROJECT-[A-Z]+'
trace redact list
trace check
trace ci main..HEAD
```

From a checkout, the same commands can be run without installing:

```shell
node trace/bin/trace.mjs init
node trace/bin/trace.mjs enable
node trace/bin/trace.mjs agent add codex
node trace/bin/trace.mjs agent add claude-code
node trace/bin/trace.mjs agent add gemini
node trace/bin/trace.mjs capture --event prompt --role user --message "why this change exists"
node trace/bin/trace.mjs record --validation "npm test"
node trace/bin/trace.mjs show HEAD
node trace/bin/trace.mjs log
node trace/bin/trace.mjs index
node trace/bin/trace.mjs search "auth retry"
node trace/bin/trace.mjs search --field decisions "retry"
node trace/bin/trace.mjs search --field files "auth"
node trace/bin/trace.mjs summary main..HEAD
node trace/bin/trace.mjs pr-body main..HEAD
node trace/bin/trace.mjs release-notes v1.0.0..HEAD
node trace/bin/trace.mjs checkpoint list
node trace/bin/trace.mjs checkpoint verify
node trace/bin/trace.mjs checkpoint push origin --dry-run
node trace/bin/trace.mjs checkpoint cleanup --sessions-before-days 14
node trace/bin/trace.mjs redact add codename 'PROJECT-[A-Z]+'
node trace/bin/trace.mjs redact list
node trace/bin/trace.mjs check
node trace/bin/trace.mjs ci main..HEAD
```

`trace enable` installs managed `prepare-commit-msg` and `post-commit` git hook blocks. The prepare hook adds `Trace-Checkpoint` and `Trace-Session` trailers to the commit message. The post-commit hook writes a compact memory file under `.trace/commits/` and stores the raw checkpoint payload on the local `refs/trace/checkpoints` git ref.

This keeps the project tree focused on reviewable memories while raw checkpoint data stays outside the normal branch history unless someone explicitly pushes the Trace ref.

Because post-commit hooks run after git creates the commit, generated `.trace/commits/` memories are left as normal working tree changes for the user or agent to review and commit. `trace check` fails when Trace memory files are uncommitted or malformed, which makes that handoff explicit instead of silently pretending the memory is already durable.

`trace ci <range>` is the CI gate for that model. It fails when non-Trace commits in the range do not have a committed `.trace/commits/<sha-prefix>/<sha>.md` memory, while skipping Trace-only memory commits so memory can be committed in a follow-up commit. It also fails if raw transcript or checkpoint-shaped files appear in the normal `.trace/` project tree, such as `.trace/sessions/*.jsonl`, `.trace/raw/`, `.trace/checkpoints/`, or transcript dumps. Reviewable memories, `.trace/config.json`, and local agent adapter specs are allowed.

`trace summary <range>`, `trace pr-body <range>`, and `trace release-notes <range>` all derive from committed memories. PR and release text are generated views, not the canonical memory store.

`trace index` builds a rebuildable search cache in the git common directory, outside the project tree. `trace search` rebuilds that cache when committed memories change and can search all memory text or a specific field such as `decisions`, `files`, `validation`, or `risks`.

Agent integrations can use first-class adapters or the generic hook endpoint:

```shell
printf '{"session_id":"abc","agent":"codex","prompt":"why this task exists"}' \
  | trace hook agent --adapter codex

printf '{"hook_event_name":"UserPromptSubmit","prompt":"why this task exists"}' \
  | trace hook agent --adapter claude-code

printf '{"kind":"model_response","content":"implemented the requested change"}' \
  | trace hook agent --adapter gemini
```

The hook accepts JSON or plain text on stdin and records it into the local raw session store. The Codex, Claude Code, Gemini, and generic adapters normalize provider payloads into Trace lifecycle events: prompt, response, tool, decision, validation, risk, and note. Tool payloads are compacted into one-line activity entries, while full raw session data stays in the git common directory.

`trace/install.sh` installs a `trace` symlink into `$HOME/.local/bin` by default. Use `--prefix <dir>` or `TRACE_INSTALL_DIR=<dir>` to install elsewhere. `--update` refreshes the symlink to the current checkout, and `--uninstall` removes it.

`trace agent add codex`, `trace agent add claude-code`, `trace agent add gemini`, and `trace agent add generic` create small local adapter specs under `.trace/agents/`. The specs document the command an agent integration should call:

```shell
trace hook agent --adapter codex
```

This keeps the first version agent-agnostic while making the hook contract explicit and reviewable.

Checkpoint commands keep the raw side of Trace explicit:

- `trace checkpoint list` shows checkpoint payloads stored on `refs/trace/checkpoints`.
- `trace checkpoint verify` checks checkpoint payload shape, commit reachability, and stored SHA-256 integrity metadata.
- `trace checkpoint push <remote>` and `trace checkpoint fetch <remote>` sync only the Trace checkpoint ref.
- `trace checkpoint cleanup --sessions-before-days 14` prunes old local raw session JSONL files from the git common directory.

Redaction is local and configurable. Built-in rules scrub common token/password shapes and high-entropy strings. Custom rules live in `.trace/config.json`:

```shell
trace redact add codename 'PROJECT-[A-Z]+'
trace redact remove codename
```

Custom matches are replaced with labeled placeholders like `[REDACTED_CODENAME]` before raw events or commit memories are written.
