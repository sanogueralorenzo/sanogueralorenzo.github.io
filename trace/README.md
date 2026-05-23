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
trace install --prefix "$HOME/.local/bin"
trace install update --prefix "$HOME/.local/bin"
trace install uninstall --prefix "$HOME/.local/bin"
trace capture --event prompt --role user --message "why this change exists"
trace capture --event risk --message "token=secret" --dry-run
trace hook agent --adapter codex --dry-run
trace run -- npm test
trace session start task-auth-retry
trace session end task-auth-retry
trace session list
trace session show <session>
trace session recap <session>
trace session recap <session> --field handoff
trace session recap <session> --field handoff --output trace-session-recap.md
trace session check <session>
trace session check --strict <session>
trace record --dry-run --validation "npm test"
trace record --check-session --validation "npm test"
trace record --check-session --strict --validation "npm test"
trace record --validation "npm test"
trace show HEAD
trace show HEAD --json
trace show HEAD --output trace-memory.md
trace review
trace review --output trace-review.md
trace log
trace log --json --limit 20
trace index
trace search "auth retry"
trace search --field intent "why auth changed"
trace search --field agents "codex"
trace search --field lifecycle "validation"
trace search --field summary "fixture"
trace search --field decisions "retry"
trace search --field tools "git commit"
trace search --field files "auth"
trace search --field validation "npm test"
trace search --field risks "timeout"
trace search --field handoff "preserve"
trace search --field session <session>
trace search --json --limit 5 "auth retry"
trace search --field decisions "retry" --output trace-search.txt
trace recall "auth retry"
trace recall --field agents "codex"
trace recall --field lifecycle "validation"
trace recall --field decisions "retry"
trace recall --field validation "npm test"
trace recall --files src/auth.ts
trace recall --checkpoint <checkpoint>
trace recall --session <session>
trace recall --json "auth retry"
trace recall "auth retry" --output trace-recall.md
trace summary main..HEAD
trace branch-summary feature --base main
trace pr-body main..HEAD
trace pr-body main..HEAD --output trace-pr-body.md
trace release-notes v1.0.0..HEAD
trace pr-body main..HEAD --json
trace checkpoint list
trace checkpoint list --limit 20
trace checkpoint show <checkpoint>
trace checkpoint status origin
trace checkpoint verify
trace checkpoint push origin --dry-run
trace checkpoint export --output trace-checkpoints.json
trace checkpoint import trace-checkpoints.json
trace checkpoint import trace-checkpoints.json --dry-run
trace checkpoint cleanup --sessions-before-days 14 --keep 100 --dry-run
trace checkpoint cleanup --sessions-before-days 14 --keep 100
trace redact add codename 'PROJECT-[A-Z]+'
trace redact list
trace redact preview --text 'PROJECT-ORION token=secret'
trace redact audit
trace doctor
trace doctor --strict-memory
trace check
trace check --checkpoints
trace check --strict-memory
trace coverage main..HEAD
trace coverage main..HEAD --agents --checkpoints --strict-memory
trace ci main..HEAD --agents --checkpoints
trace ci main..HEAD --strict-memory
```

From a checkout, the same commands can be run without installing:

```shell
node trace/bin/trace.mjs init
node trace/bin/trace.mjs enable
node trace/bin/trace.mjs agent add all
node trace/bin/trace.mjs agent add codex
node trace/bin/trace.mjs agent add claude-code
node trace/bin/trace.mjs agent add gemini
node trace/bin/trace.mjs install --prefix "$HOME/.local/bin"
node trace/bin/trace.mjs install update --prefix "$HOME/.local/bin"
node trace/bin/trace.mjs install uninstall --prefix "$HOME/.local/bin"
node trace/bin/trace.mjs capture --event prompt --role user --message "why this change exists"
node trace/bin/trace.mjs capture --event risk --message "token=secret" --dry-run
node trace/bin/trace.mjs hook agent --adapter codex --dry-run
node trace/bin/trace.mjs run -- npm test
node trace/bin/trace.mjs session start task-auth-retry
node trace/bin/trace.mjs session end task-auth-retry
node trace/bin/trace.mjs session list
node trace/bin/trace.mjs session show <session>
node trace/bin/trace.mjs session recap <session>
node trace/bin/trace.mjs session recap <session> --field handoff
node trace/bin/trace.mjs session recap <session> --field handoff --output trace-session-recap.md
node trace/bin/trace.mjs session check <session>
node trace/bin/trace.mjs session check --strict <session>
node trace/bin/trace.mjs record --dry-run --validation "npm test"
node trace/bin/trace.mjs record --check-session --validation "npm test"
node trace/bin/trace.mjs record --check-session --strict --validation "npm test"
node trace/bin/trace.mjs record --validation "npm test"
node trace/bin/trace.mjs show HEAD
node trace/bin/trace.mjs show HEAD --json
node trace/bin/trace.mjs show HEAD --output trace-memory.md
node trace/bin/trace.mjs review
node trace/bin/trace.mjs review --output trace-review.md
node trace/bin/trace.mjs log
node trace/bin/trace.mjs log --json --limit 20
node trace/bin/trace.mjs index
node trace/bin/trace.mjs search "auth retry"
node trace/bin/trace.mjs search --field intent "why auth changed"
node trace/bin/trace.mjs search --field agents "codex"
node trace/bin/trace.mjs search --field lifecycle "validation"
node trace/bin/trace.mjs search --field summary "fixture"
node trace/bin/trace.mjs search --field decisions "retry"
node trace/bin/trace.mjs search --field tools "git commit"
node trace/bin/trace.mjs search --field files "auth"
node trace/bin/trace.mjs search --field validation "npm test"
node trace/bin/trace.mjs search --field risks "timeout"
node trace/bin/trace.mjs search --field session <session>
node trace/bin/trace.mjs search --json --limit 5 "auth retry"
node trace/bin/trace.mjs search --field decisions "retry" --output trace-search.txt
node trace/bin/trace.mjs recall "auth retry"
node trace/bin/trace.mjs recall --field agents "codex"
node trace/bin/trace.mjs recall --field lifecycle "validation"
node trace/bin/trace.mjs recall --field decisions "retry"
node trace/bin/trace.mjs recall --field validation "npm test"
node trace/bin/trace.mjs recall --files src/auth.ts
node trace/bin/trace.mjs recall --checkpoint <checkpoint>
node trace/bin/trace.mjs recall --session <session>
node trace/bin/trace.mjs recall --json "auth retry"
node trace/bin/trace.mjs recall "auth retry" --output trace-recall.md
node trace/bin/trace.mjs summary main..HEAD
node trace/bin/trace.mjs branch-summary feature --base main
node trace/bin/trace.mjs pr-body main..HEAD
node trace/bin/trace.mjs pr-body main..HEAD --output trace-pr-body.md
node trace/bin/trace.mjs release-notes v1.0.0..HEAD
node trace/bin/trace.mjs pr-body main..HEAD --json
node trace/bin/trace.mjs checkpoint list
node trace/bin/trace.mjs checkpoint list --limit 20
node trace/bin/trace.mjs checkpoint show <checkpoint>
node trace/bin/trace.mjs checkpoint status origin
node trace/bin/trace.mjs checkpoint verify
node trace/bin/trace.mjs checkpoint push origin --dry-run
node trace/bin/trace.mjs checkpoint export --output trace-checkpoints.json
node trace/bin/trace.mjs checkpoint import trace-checkpoints.json
node trace/bin/trace.mjs checkpoint import trace-checkpoints.json --dry-run
node trace/bin/trace.mjs checkpoint cleanup --sessions-before-days 14 --keep 100 --dry-run
node trace/bin/trace.mjs checkpoint cleanup --sessions-before-days 14 --keep 100
node trace/bin/trace.mjs redact add codename 'PROJECT-[A-Z]+'
node trace/bin/trace.mjs redact list
node trace/bin/trace.mjs redact preview --text 'PROJECT-ORION token=secret'
node trace/bin/trace.mjs redact audit
node trace/bin/trace.mjs doctor
node trace/bin/trace.mjs doctor --strict-memory
node trace/bin/trace.mjs check
node trace/bin/trace.mjs check --strict-memory
node trace/bin/trace.mjs coverage main..HEAD
node trace/bin/trace.mjs coverage main..HEAD --agents --checkpoints --strict-memory
node trace/bin/trace.mjs ci main..HEAD
node trace/bin/trace.mjs ci main..HEAD --strict-memory
```

`trace enable` installs managed `pre-commit`, `prepare-commit-msg`, and `post-commit` git hook blocks. The pre-commit hook blocks raw transcript or checkpoint-shaped files from being committed under `.trace/`. The prepare hook adds `Trace-Checkpoint` and `Trace-Session` trailers to the commit message. The post-commit hook writes a compact memory file under `.trace/commits/` and stores the raw checkpoint payload on the local `refs/trace/checkpoints` git ref.

This keeps the project tree focused on reviewable memories while raw checkpoint data stays outside the normal branch history unless someone explicitly pushes the Trace ref.

Because post-commit hooks run after git creates the commit, generated `.trace/commits/` memories are left as normal working tree changes for the user or agent to review and commit. `trace show <commit>` displays the exact committed Markdown memory for one commit; add `--json` for structured memory detail or `--output <file>` to write either form for handoff while stdout returns a small schema-stable write result. `trace review` shows the pending memory review queue with checkpoint/session identity, intent, summary, decisions, affected files, validation, risks, and future-agent handoff before those files are committed. Add `--output <file>` to write that redacted review queue as Markdown or JSON while stdout returns a small schema-stable write result. `trace check` fails when Trace memory files are uncommitted, use an unsupported schema, point at a commit that is not reachable, are stored at the wrong commit-derived path, are missing checkpoint/session metadata, or are missing required sections, which makes that handoff explicit instead of silently pretending the memory is already durable. Add `--checkpoints` to also require a present, valid checkpoint ref with payloads for committed memories, and `--strict-memory` to require committed memories to contain intent, decision, and validation signals.

`trace record` and the post-commit hook distill raw session events into compact commit memory. When a commit already has `Trace-Checkpoint` or `Trace-Session` trailers, `trace record` reuses those identities so manual recording stays aligned with hook-created commits. Repeated events are deduplicated, local session lifecycle notes are kept in the raw checkpoint but excluded from the reviewable summary, adapter/source provenance is promoted into the reviewable `Agents` section, event counts are promoted into the reviewable `Lifecycle` section, long entries are truncated, noisy sections are capped with an explicit omitted-events line, and labeled response lines such as `Decision:`, `Validation:`, and `Risk:` are promoted into the right memory sections. A short `Handoff` section is derived from the visible decision, validation, risks, and changed files so future agents know what to preserve or recheck while the full checkpoint remains available on the Trace ref. `trace record` emits a schema-stable JSON result with structured `memoryPreview` and `checkpointPreview` alongside write results, and `trace record --dry-run` previews the same Markdown and previews without writing `.trace/commits/` or updating `refs/trace/checkpoints`. Use `trace record --check-session` to fail before writing when the selected session only contains local lifecycle notes, and `trace record --check-session --strict` when the session must include intent, decision, and validation signals.

`trace capture` only accepts the supported lifecycle events: prompt, response, tool, decision, validation, risk, and note, and emits a schema-stable JSON result for manual lifecycle capture. Add `--dry-run` to preview the normalized, redacted event without writing local session state. This keeps manual captures, adapter events, search fields, and generated memories aligned to one stable taxonomy. `trace hook agent` emits a schema-stable JSON result for single and batched adapter captures. `trace hook agent --dry-run` returns the normalized, redacted lifecycle events for an adapter payload without writing `.trace/config.json`, session JSONL, or current-session state, so integrations can test their mapping before they capture real memory.

`trace run -- <command>` executes a local validation or tool command, streams its output, records the command result plus compact stdout/stderr into the current raw session, and exits with the same code. Successful commands become `validation` events by default; failed commands become `risk` events. Use `--event tool` when the command is tool activity rather than validation.

`trace session start [session-id]` starts or switches the current local lifecycle session without writing raw data into the project tree and records a local lifecycle note. `trace session end [session-id]` records the close note, then clears the current session pointer without deleting raw session events, which keeps the next task from accidentally reusing stale context. `trace session list`, `trace session current`, and `trace session show <session>` inspect the local raw lifecycle store in the git common directory. `trace session recap <session>` turns the local raw events into a redacted Markdown or JSON preview using the same prompt, response, tool, decision, validation, risk, note, and future-agent handoff taxonomy that commit memory generation uses; add `--field handoff`, `--field decisions`, or another recap field to inspect only that memory slice. Add `--output <file>` to write the redacted Markdown or JSON recap as a reviewable handoff while stdout returns a small schema-stable write result. `trace session check <session>` fails when a session only contains local lifecycle notes and reports warnings for missing intent, decision, or validation signals before an agent records memory; add `--strict` to fail on those missing intent, decision, or validation warnings too. This gives agents a way to debug capture coverage and event shape without writing transcripts into the project tree.

`trace coverage <range>` reports commit-by-commit memory status, covered/missing/skipped counts, and unsafe Trace files. Add `--agents`, `--checkpoints`, or `--strict-memory` to preview the same adapter contract, checkpoint integrity, and memory quality findings that CI can gate on without turning the report command itself into a failing gate. `trace ci <range>` uses the same report as a gate: it fails when non-Trace commits in the range do not have a committed `.trace/commits/<sha-prefix>/<sha>.md` memory, while skipping Trace-only memory commits so memory can be committed in a follow-up commit. It also fails when committed memory files are malformed, contain unredacted secrets, or when raw transcript or checkpoint-shaped files appear in the normal `.trace/` project tree, such as `.trace/sessions/*.jsonl`, `.trace/raw/`, `.trace/checkpoints/`, or transcript dumps. Reviewable memories, `.trace/config.json`, and local agent adapter specs are allowed. Add `--agents` to make CI also run the installed adapter contract fixtures for every supported first-class agent, `--checkpoints` to require a present, valid `refs/trace/checkpoints` ref with checkpoint payloads for covered memories in the checked range, and `--strict-memory` to require committed memories to contain intent, decision, and validation signals.

`trace summary <range>`, `trace branch-summary <branch> --base <base>`, `trace pr-body <range>`, and `trace release-notes <range>` all derive from committed memories, including adapter provenance, lifecycle event counts, and the future-agent handoff section. Branch, PR, and release text are generated views, not the canonical memory store. Add `--json` to emit the same memory-derived summary as structured data for agents and CI automation, including per-commit memory path, checkpoint, session, agents, lifecycle, files, validation, risks, and handoff. Add `--output <file>` to write the derived Markdown or JSON to a file while stdout returns a small schema-stable write result.

`trace index` builds a rebuildable search cache in the git common directory, outside the project tree. `trace search` rebuilds that cache when committed memories change, ranks matches by term frequency, and can search all memory text or a specific field such as `agents`, `lifecycle`, `intent`, `summary`, `decisions`, `responses`, `tools`, `files`, `checkpoint`, `session`, `validation`, `risks`, or `handoff`. Use `--json` and `--limit` when agents need structured local search results with score, commit, memory path, checkpoint, and session identity. Add `--output <file>` to write text or JSON search results for an agent handoff while stdout returns a small schema-stable write result.

`trace recall <query>` returns an agent-ready Markdown context bundle from the most relevant committed memories. It includes the original memory path, checkpoint/session identity, adapter provenance, lifecycle event counts, intent, summary, decisions, responses, tool activity, files, validation, risks, and handoff. Add `--field agents`, `--field lifecycle`, `--field decisions`, `--field validation`, or another memory field to recall context from that specific part of committed memories. `trace recall --files src/auth.ts` ranks memories by affected files, `trace recall --checkpoint <checkpoint>` and `trace recall --session <session>` jump directly from Trace identity back to committed memories, plain `trace recall` uses locally changed files when available, and `--json` emits the same recall bundle as structured data. Add `--output <file>` to write the Markdown or JSON bundle for an agent handoff while stdout returns a small schema-stable write result.

`trace doctor` audits the local Trace installation in one read-only command: config, CLI install health, managed hook commands, adapter contract specs, committed memory shape, uncommitted Trace files, checkpoint ref integrity, checkpoint links from committed memories, and search index freshness. Add `--strict-memory` to include the same committed-memory intent, decision, and validation quality gate used by `trace check` and CI. Missing CLI installs and stale rebuildable caches are warnings, while missing or tampered hooks, malformed memory files, malformed adapter configs, missing linked checkpoint payloads, checkpoint integrity errors, and strict memory quality findings fail the command.

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

`trace/install.sh` installs a `trace` symlink into `$HOME/.local/bin` by default. Use `--prefix <dir>` or `TRACE_INSTALL_DIR=<dir>` to install elsewhere. `--update` refreshes the symlink to the current checkout, `--status` reports the same install state as `trace install status`, and `--uninstall` removes it. `trace install [install|update|uninstall|status] [--prefix <dir>]` provides the same local install flow from the CLI and returns schema-stable JSON for automation. The status output reports whether the expected symlink is installed, whether it points at the current checkout, and the exact install/update/uninstall commands for that prefix. `trace status` includes the same install health alongside repository hooks, adapters, raw storage, and checkpoint ref state.

`trace agent add all` creates local adapter specs for every supported first-class adapter. `trace agent add codex`, `trace agent add claude-code`, `trace agent add gemini`, and `trace agent add generic` create a single spec under `.trace/agents/`. The specs document the command an agent integration should call:

```shell
trace hook agent --adapter codex
```

This keeps the first version agent-agnostic while making the hook contract explicit and reviewable. `trace agent list` and `trace doctor` validate that each adapter spec uses the supported schema, adapter command, stdin mode, lifecycle events, and fixture contract. `trace agent check [agent|all]` also runs the adapter contract fixtures from `trace/examples/` so CI can prove that configured adapters still normalize representative payloads into the expected lifecycle events.

Checkpoint commands keep the raw side of Trace explicit:

- `trace checkpoint list` shows checkpoint payloads stored on `refs/trace/checkpoints`; add `--limit` to inspect only the newest local checkpoint summaries.
- `trace checkpoint show <checkpoint>` inspects one local checkpoint payload without copying raw data into the project tree; add `--json` when an agent needs the full structured payload.
- `trace checkpoint status <remote>` compares the local checkpoint ref with a remote ref and prints the exact push/fetch commands needed to sync it.
- `trace checkpoint verify` checks checkpoint payload shape, commit reachability, and stored SHA-256 integrity metadata.
- `trace checkpoint push <remote>` and `trace checkpoint fetch <remote>` sync only the Trace checkpoint ref and return a schema-stable before/after status for automation.
- `trace checkpoint export --output trace-checkpoints.json` and `trace checkpoint import trace-checkpoints.json` move checkpoint payloads through an explicit local bundle without using a hosted service; add `--dry-run` to validate and preview an import without rewriting `refs/trace/checkpoints`.
- `trace checkpoint cleanup --sessions-before-days 14 --keep 100` prunes old local raw session JSONL files from the git common directory and rewrites the checkpoint ref to retain only the newest checkpoint payloads when `--keep` is provided; add `--dry-run` to preview the exact removals without deleting sessions or rewriting the ref.

Redaction is local and configurable. Built-in rules scrub common token/password shapes, environment-style secret names such as `OPENAI_API_KEY` and `GITHUB_TOKEN`, authorization headers, and high-entropy strings. Custom rules live in `.trace/config.json`:

```shell
trace redact add codename 'PROJECT-[A-Z]+'
trace redact preview --text 'PROJECT-ORION token=secret'
trace redact audit
trace redact remove codename
```

Custom matches are replaced with labeled placeholders like `[REDACTED_CODENAME]` before raw events or commit memories are written. `trace redact preview` applies the active built-in and custom rules to text or stdin without writing state, so agents can verify local rules before capture. `trace redact audit` scans committed memories, local raw session files, and checkpoint ref payloads for unredacted secret assignments or configured custom patterns, and `trace doctor` includes the same audit.
