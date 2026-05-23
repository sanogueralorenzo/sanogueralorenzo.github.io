# Intent Roadmap

This roadmap turns the language concept into an implementable project.

## Phase 1: Written Contract

- Define the language surface in `SPEC.md`.
- Keep examples aligned with the same syntax.
- Split design work into focused workstreams for language, tools, trust, memory, verification, and examples.
- Record unresolved decisions instead of hiding them in prose.

## Phase 2: Static Model

- Implement a parser for packages, goals, contexts, capabilities, memory, plans, verification, and invariants. Initial CLI: `node intent/bin/intent.mjs parse <file.intent>`.
- Build an abstract syntax tree that preserves source locations. Initial schema: `intent.ast.v0`.
- Add a checker that rejects undeclared effects, missing verification gates, unsafe trust flows, and unscoped memory. Initial CLI: `node intent/bin/intent.mjs check <file.intent>`.
- Emit a machine-readable execution graph. Initial schema: `intent.graph.v0`, via `node intent/bin/intent.mjs graph <file.intent>`.
- Keep fixtures under `fixtures/` and tests under `test/`.

## Phase 3: Local Runtime

- Execute graph steps through local adapters.
- Support shell, file, web-read, and human-approval adapters first.
- Persist checkpoints after every completed step and after every irreversible
  effect before completion or another irreversible effect.
- Record provenance for commands, file reads, file writes, approvals, and final outputs.

## Phase 4: Trust And Memory

- Add trust zones for repository content, user messages, public web data, secrets, and tool outputs.
- Prevent untrusted text from becoming executable commands without an explicit policy transition.
- Implement scoped memory with retention, promotion, and erasure.
- Make provenance queryable from every final artifact.

## Phase 5: Verification

- Make verification gates mandatory for goal completion.
- Re-run stale checks when relevant inputs change.
- Add policy checks for secrets, unrelated file writes, missing citations, and missing approvals.
- Produce a completion report that lists evidence for every required gate.

## Phase 6: Developer Experience

- Add formatter and linter commands.
- Add editor highlighting.
- Add a small standard library of reusable capability and verification definitions.
- Publish runnable examples.

## Non-Goals For The First Prototype

- General-purpose application programming.
- Full distributed scheduling.
- Arbitrary plugin execution without capability declarations.
- Silent compatibility with prompt-only agents.
- Hidden global memory.
