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
./trace/install.sh --status
./trace/install.sh --uninstall
trace install status
trace init
trace enable
trace agent add all
trace agent add codex
trace agent add claude-code
trace agent add gemini
trace agent check all
trace capture --event prompt --role user --message "why this change exists"
trace run -- npm test
trace session start task-auth-retry
trace session end task-auth-retry
trace session list
trace session show <session>
trace record --validation "npm test"
trace show HEAD
trace show HEAD --json
trace review
trace log
trace log --json --limit 20
trace index
trace search "auth retry"
trace search --field decisions "retry"
trace search --field files "auth"
trace search --field handoff "preserve"
trace search --json --limit 5 "auth retry"
trace recall "auth retry"
trace recall --files src/auth.ts
trace recall --json "auth retry"
trace summary main..HEAD
trace branch-summary feature --base main
trace pr-body main..HEAD
trace release-notes v1.0.0..HEAD
trace pr-body main..HEAD --json
trace checkpoint list
trace checkpoint status origin
trace checkpoint verify
trace checkpoint push origin --dry-run
trace checkpoint export --output trace-checkpoints.json
trace checkpoint import trace-checkpoints.json
trace checkpoint cleanup --sessions-before-days 14 --keep 100
trace redact add codename 'PROJECT-[A-Z]+'
trace redact list
trace redact audit
trace doctor
trace check
trace check --checkpoints
trace coverage main..HEAD
trace ci main..HEAD --agents --checkpoints
```

From a checkout, the same commands can be run without installing:

```shell
node trace/bin/trace.mjs init
node trace/bin/trace.mjs enable
node trace/bin/trace.mjs agent add all
node trace/bin/trace.mjs agent add codex
node trace/bin/trace.mjs agent add claude-code
node trace/bin/trace.mjs agent add gemini
node trace/bin/trace.mjs capture --event prompt --role user --message "why this change exists"
node trace/bin/trace.mjs run -- npm test
node trace/bin/trace.mjs session start task-auth-retry
node trace/bin/trace.mjs session end task-auth-retry
node trace/bin/trace.mjs session list
node trace/bin/trace.mjs session show <session>
node trace/bin/trace.mjs record --validation "npm test"
node trace/bin/trace.mjs show HEAD
node trace/bin/trace.mjs show HEAD --json
node trace/bin/trace.mjs review
node trace/bin/trace.mjs log
node trace/bin/trace.mjs log --json --limit 20
node trace/bin/trace.mjs index
node trace/bin/trace.mjs search "auth retry"
node trace/bin/trace.mjs search --field decisions "retry"
node trace/bin/trace.mjs search --field files "auth"
node trace/bin/trace.mjs search --json --limit 5 "auth retry"
node trace/bin/trace.mjs recall "auth retry"
node trace/bin/trace.mjs recall --files src/auth.ts
node trace/bin/trace.mjs recall --json "auth retry"
node trace/bin/trace.mjs summary main..HEAD
node trace/bin/trace.mjs branch-summary feature --base main
node trace/bin/trace.mjs pr-body main..HEAD
node trace/bin/trace.mjs release-notes v1.0.0..HEAD
node trace/bin/trace.mjs pr-body main..HEAD --json
node trace/bin/trace.mjs checkpoint list
node trace/bin/trace.mjs checkpoint status origin
node trace/bin/trace.mjs checkpoint verify
node trace/bin/trace.mjs checkpoint push origin --dry-run
node trace/bin/trace.mjs checkpoint export --output trace-checkpoints.json
node trace/bin/trace.mjs checkpoint import trace-checkpoints.json
node trace/bin/trace.mjs checkpoint cleanup --sessions-before-days 14 --keep 100
node trace/bin/trace.mjs redact add codename 'PROJECT-[A-Z]+'
node trace/bin/trace.mjs redact list
node trace/bin/trace.mjs redact audit
node trace/bin/trace.mjs doctor
node trace/bin/trace.mjs check
node trace/bin/trace.mjs coverage main..HEAD
node trace/bin/trace.mjs ci main..HEAD
```

`trace enable` installs managed `pre-commit`, `prepare-commit-msg`, and `post-commit` git hook blocks. The pre-commit hook blocks raw transcript or checkpoint-shaped files from being committed under `.trace/`. The prepare hook adds `Trace-Checkpoint` and `Trace-Session` trailers to the commit message. The post-commit hook writes a compact memory file under `.trace/commits/` and stores the raw checkpoint payload on the local `refs/trace/checkpoints` git ref.

This keeps the project tree focused on reviewable memories while raw checkpoint data stays outside the normal branch history unless someone explicitly pushes the Trace ref.

Because post-commit hooks run after git creates the commit, generated `.trace/commits/` memories are left as normal working tree changes for the user or agent to review and commit. `trace review` shows the pending memory review queue with checkpoint/session identity, intent, summary, decisions, affected files, validation, risks, and future-agent handoff before those files are committed. `trace check` fails when Trace memory files are uncommitted, use an unsupported schema, point at a commit that is not reachable, are stored at the wrong commit-derived path, are missing checkpoint/session metadata, or are missing required sections, which makes that handoff explicit instead of silently pretending the memory is already durable. Add `--checkpoints` to also require a present, valid checkpoint ref with payloads for committed memories.

`trace record` and the post-commit hook distill raw session events into compact commit memory. When a commit already has `Trace-Checkpoint` or `Trace-Session` trailers, `trace record` reuses those identities so manual recording stays aligned with hook-created commits. Repeated events are deduplicated, long entries are truncated, noisy sections are capped with an explicit omitted-events line, and a short `Handoff` section is derived from the visible decision, validation, risks, and changed files so future agents know what to preserve or recheck while the full checkpoint remains available on the Trace ref.

`trace capture` only accepts the supported lifecycle events: prompt, response, tool, decision, validation, risk, and note. This keeps manual captures, adapter events, search fields, and generated memories aligned to one stable taxonomy.

`trace run -- <command>` executes a local validation or tool command, streams its output, records the command result plus compact stdout/stderr into the current raw session, and exits with the same code. Successful commands become `validation` events by default; failed commands become `risk` events. Use `--event tool` when the command is tool activity rather than validation.

`trace session start [session-id]` starts or switches the current local lifecycle session without writing raw data into the project tree. `trace session end [session-id]` clears the current session pointer without deleting raw session events, which keeps the next task from accidentally reusing stale context. `trace session list`, `trace session current`, and `trace session show <session>` inspect the local raw lifecycle store in the git common directory. This gives agents a way to debug capture coverage and event shape without writing transcripts into the project tree.

`trace coverage <range>` reports commit-by-commit memory status, covered/missing/skipped counts, and unsafe Trace files. `trace ci <range>` uses the same report as a gate: it fails when non-Trace commits in the range do not have a committed `.trace/commits/<sha-prefix>/<sha>.md` memory, while skipping Trace-only memory commits so memory can be committed in a follow-up commit. It also fails when committed memory files are malformed, contain unredacted secrets, or when raw transcript or checkpoint-shaped files appear in the normal `.trace/` project tree, such as `.trace/sessions/*.jsonl`, `.trace/raw/`, `.trace/checkpoints/`, or transcript dumps. Reviewable memories, `.trace/config.json`, and local agent adapter specs are allowed. Add `--agents` to make CI also run the installed adapter contract fixtures for every supported first-class agent, and `--checkpoints` to require a present, valid `refs/trace/checkpoints` ref with checkpoint payloads for covered memories in the checked range.

`trace summary <range>`, `trace branch-summary <branch> --base <base>`, `trace pr-body <range>`, and `trace release-notes <range>` all derive from committed memories, including the future-agent handoff section. Branch, PR, and release text are generated views, not the canonical memory store. Add `--json` to emit the same memory-derived summary as structured data for agents and CI automation.

`trace index` builds a rebuildable search cache in the git common directory, outside the project tree. `trace search` rebuilds that cache when committed memories change and can search all memory text or a specific field such as `decisions`, `files`, `validation`, `risks`, or `handoff`. Use `--json` and `--limit` when agents need structured local search results.

`trace recall <query>` returns an agent-ready Markdown context bundle from the most relevant committed memories. It includes the original memory path plus intent, summary, decisions, validation, risks, and handoff. `trace recall --files src/auth.ts` ranks memories by affected files, plain `trace recall` uses locally changed files when available, and `--json` emits the same recall bundle as structured data.

`trace doctor` audits the local Trace installation in one read-only command: config, CLI install health, managed hook commands, adapter contract specs, committed memory shape, uncommitted Trace files, checkpoint ref integrity, and search index freshness. Missing CLI installs and stale rebuildable caches are warnings, while missing or tampered hooks, malformed memory files, malformed adapter configs, and checkpoint integrity errors fail the command.

Agent integrations can use first-class adapters or the generic hook endpoint:

```shell
printf '{"session_id":"abc","agent":"codex","prompt":"why this task exists"}' \
  | trace hook agent --adapter codex

printf '{"hook_event_name":"UserPromptSubmit","prompt":"why this task exists"}' \
  | trace hook agent --adapter claude-code

printf '{"kind":"model_response","content":"implemented the requested change"}' \
  | trace hook agent --adapter gemini
```

The hook accepts JSON or plain text on stdin and records it into the local raw session store. The Codex, Claude Code, Gemini, and generic adapters normalize provider payloads into Trace lifecycle events: prompt, response, tool, decision, validation, risk, and note. Payloads can also include structured `decisions`, `validations`, `risks`, `tools`, `notes`, `prompts`, or `responses` fields; Trace expands those into separate lifecycle events so one agent summary can feed the eventual commit memory. Tool payloads are compacted into one-line activity entries, while full raw session data stays in the git common directory.

Adapters may also send a JSON array or newline-delimited JSON objects to `trace hook agent` when a provider emits multiple lifecycle events at once. Trace records each item as an ordered event in the same local session.

See `trace/examples/` for complete local workflows covering adapter capture, commit memory review, PR/release summaries, and CI checks.

`trace/install.sh` installs a `trace` symlink into `$HOME/.local/bin` by default. Use `--prefix <dir>` or `TRACE_INSTALL_DIR=<dir>` to install elsewhere. `--update` refreshes the symlink to the current checkout, `--status` reports the same install state as `trace install status`, and `--uninstall` removes it. `trace install status [--prefix <dir>]` reports whether the expected symlink is installed, whether it points at the current checkout, and the exact install/update/uninstall commands for that prefix. `trace status` includes the same install health alongside repository hooks, adapters, raw storage, and checkpoint ref state.

`trace agent add all` creates local adapter specs for every supported first-class adapter. `trace agent add codex`, `trace agent add claude-code`, `trace agent add gemini`, and `trace agent add generic` create a single spec under `.trace/agents/`. The specs document the command an agent integration should call:

```shell
trace hook agent --adapter codex
```

This keeps the first version agent-agnostic while making the hook contract explicit and reviewable. `trace agent list` and `trace doctor` validate that each adapter spec uses the supported schema, adapter command, stdin mode, lifecycle events, and fixture contract. `trace agent check [agent|all]` also runs the adapter contract fixtures from `trace/examples/` so CI can prove that configured adapters still normalize representative payloads into the expected lifecycle events.

Checkpoint commands keep the raw side of Trace explicit:

- `trace checkpoint list` shows checkpoint payloads stored on `refs/trace/checkpoints`.
- `trace checkpoint status <remote>` compares the local checkpoint ref with a remote ref and prints the exact push/fetch commands needed to sync it.
- `trace checkpoint verify` checks checkpoint payload shape, commit reachability, and stored SHA-256 integrity metadata.
- `trace checkpoint push <remote>` and `trace checkpoint fetch <remote>` sync only the Trace checkpoint ref.
- `trace checkpoint export --output trace-checkpoints.json` and `trace checkpoint import trace-checkpoints.json` move checkpoint payloads through an explicit local bundle without using a hosted service.
- `trace checkpoint cleanup --sessions-before-days 14 --keep 100` prunes old local raw session JSONL files from the git common directory and rewrites the checkpoint ref to retain only the newest checkpoint payloads when `--keep` is provided.

Redaction is local and configurable. Built-in rules scrub common token/password shapes, environment-style secret names such as `OPENAI_API_KEY` and `GITHUB_TOKEN`, authorization headers, and high-entropy strings. Custom rules live in `.trace/config.json`:

```shell
trace redact add codename 'PROJECT-[A-Z]+'
trace redact audit
trace redact remove codename
```

Custom matches are replaced with labeled placeholders like `[REDACTED_CODENAME]` before raw events or commit memories are written. `trace redact audit` scans committed memories, local raw session files, and checkpoint ref payloads for unredacted secret assignments or configured custom patterns, and `trace doctor` includes the same audit.
