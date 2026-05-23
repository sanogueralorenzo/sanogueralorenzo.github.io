# Intent

Intent is a draft agent-first typed workflow language.

Most programming languages are built around instructions: compute this value, call this function, mutate this state. Intent starts from a different premise: agents need a language for goals, context, permissions, memory, uncertainty, verification, and accountable side effects.

## Repository Map

- [SPEC.md](SPEC.md): the current language contract and runtime model.
- [GRAMMAR.md](GRAMMAR.md): the first parser milestone grammar.
- [STATIC_MODEL.md](STATIC_MODEL.md): AST, source location, checker, diagnostic, and graph model notes.
- [ROADMAP.md](ROADMAP.md): the path from written design to parser, checker, runtime, and developer tools.
- [fixtures/README.md](fixtures/README.md): valid and invalid `.intent` files for the prototype parser and checker.
- [examples/README.md](examples/README.md): concrete Intent goals for code changes, research, incident response, and deployment approval.
- [workstreams/language-design.md](workstreams/language-design.md): syntax, declarations, goals, type forms, uncertainty, effects, and packages.
- [workstreams/tools-and-effects.md](workstreams/tools-and-effects.md): capabilities, effect signatures, adapters, denials, approvals, and rollback contracts.
- [workstreams/trust-security.md](workstreams/trust-security.md): trust zones, principals, secrets, approvals, audit logs, policy checks, and failure modes.
- [workstreams/memory-provenance.md](workstreams/memory-provenance.md): scoped memory, retention, erasure, evidence, checkpoints, and provenance graphs.
- [workstreams/verification-runtime.md](workstreams/verification-runtime.md): execution graph semantics, step lifecycle, checks, invariants, retries, cancellation, and completion.

The core idea is simple:

```intent
goal "ship checkout fix" {
  context repo("./")
  capability file(read, write)
  capability shell(run: ["npm test", "npm run lint"])
  budget time: 30m

  plan {
    inspect failing_tests
    patch minimal
    verify with ["npm test", "npm run lint"]
    require human_approval before git_push
  }

  invariant {
    never_commit secrets
    never_modify unrelated_files
    explain external_calls
  }
}
```

## Prototype CLI

The Phase 2 static model starts as a dependency-free Node CLI:

```shell
node intent/bin/intent.mjs parse intent/fixtures/valid_code_change.intent
node intent/bin/intent.mjs check intent/fixtures/valid_code_change.intent
node intent/bin/intent.mjs graph intent/fixtures/valid_code_change.intent
node --test intent/test/*.test.mjs
```

The first implementation parses package and goal blocks, preserves source spans,
checks for missing verification, undeclared effects, capability coverage,
verification shell grants, and memory retention lifecycles, and emits versioned
JSON contracts for downstream tools.

## JSON Output Contracts

Every successful command writes formatted JSON to stdout and includes a stable
`schema_version` field:

- `parse`: emits `intent.ast.v0`, the parsed source model with package, type,
  goal, block, step, effect, and span data.
- `check`: emits `intent.check.v0`, a diagnostic envelope with `ok` and
  `diagnostics`.
- `graph`: emits `intent.graph.v0`, an execution graph envelope with
  `ast_schema_version`, `source`, `package`, `ok`, `diagnostics`, `nodes`, and
  `edges`.

The schema files for the contract milestone are expected at these paths:

- `intent/schemas/intent.ast.v0.schema.json`
- `intent/schemas/intent.check.v0.schema.json`
- `intent/schemas/intent.graph.v0.schema.json`

Schema names and `schema_version` values must move together. A breaking payload
change requires a new schema version and a new schema file instead of silently
changing an existing contract.

Validation expectations:

- Valid fixtures must parse, check with `ok: true`, and emit graph JSON with
  `ok: true`.
- Invalid fixtures must exit non-zero for `check`, emit `ok: false`, and include
  stable diagnostic codes and spans.
- AST and check schemas reject empty structural strings before downstream tools
  consume the payload. That includes AST `source` and span `file` values,
  package, type, goal, step, and parameter identifiers, capability and effect
  structural names, grant action/key/raw fields, diagnostic `code` and
  `message` fields, diagnostic span files, and string metadata that names a
  resource field, effect, family, action, scope, parameter, or step.
- Nullable descriptive fields remain nullable where the contract explicitly
  allows them, including goal titles, output types and output type spans,
  optional capability/effect actions, memory names, type definitions, and
  parsed retention subjects or lifecycle targets.
- Graph JSON with `ok: false` is for tooling/debug output only and must not be
  treated as executable by a runtime.
- Executable graph payloads must have `ok: true` and an empty `diagnostics`
  array. `ok: false` or stale diagnostics make the graph a diagnostic artifact,
  not an executable contract.
- Graph diagnostic payloads are part of the executable/diagnostic envelope
  contract. `diagnostics` must be an array, and each diagnostic must be an
  object with `severity: "error"`, non-empty `code` and `message` strings, and
  a valid `span`.
- Malformed graph diagnostic records emit a stable graph validation diagnostic
  and make the graph non-executable even when non-executable graph output is
  allowed for tooling inspection.
- Static graph validators must accept only their supported `schema_version` and
  `ast_schema_version` pair. Missing or unsupported values for either field
  emit `INTENT_GRAPH_ENVELOPE_UNSUPPORTED`.
- Executable graph payloads must include non-empty `source` and `package`
  provenance strings after trimming before runtime validation continues.
  Missing, non-string, or blank envelope provenance emits
  `INTENT_GRAPH_ENVELOPE_INVALID` before collection, node, or edge semantic
  validation because diagnostics, provenance, graph ids, and package-scoped
  runtime contracts need stable origins.
- Static graph runtimes accept only the supported node and edge kinds documented
  in `STATIC_MODEL.md`; every edge `from` and `to` endpoint must resolve to a
  node id in the same payload.
- Executable graph payloads must include `nodes` and `edges` arrays. Missing
  or non-array collections emit `INTENT_GRAPH_SHAPE_INVALID` and are not
  executable contracts.
- Executable graph payloads must contain object node records with string `id`,
  `kind`, and `label`, object `span`, and object `data`; edge records must be
  objects with string `from`, `to`, and `kind`. Malformed node or edge records
  emit stable graph shape diagnostics before endpoint, kind, or semantic
  validation.
- The graph JSON schema rejects empty structural strings before semantic graph
  validation, including graph node `id`, `kind`, and `label` values and edge
  `from` and `to` endpoint values.
- Runtime graph validation also trims structural strings and rejects
  whitespace-only graph node `id`, `kind`, and `label` values plus edge
  `from`, `to`, and `kind` values. Blank structural strings emit graph shape
  diagnostics before duplicate, endpoint, or edge-kind validation.
- Executable graph edge records may carry `data`; when present it must be an
  object. Edge `data.sourceSpan` and `data.targetSpan` payloads must be valid
  spans before runtime dependency or provenance logic can use them.
- Executable graph node spans must include a string `file` and object `start`
  and `end` positions with positive integer `line` and `column` values.
  Malformed spans emit `INTENT_GRAPH_SHAPE_INVALID` before runtime diagnostics
  depend on source locations.
- Runtime trust metadata is part of graph validation. `Context` and `Effect`
  nodes, plus verification `Check` nodes with `data.effect`, must carry valid
  `trust` records with zone `trusted`, `untrusted`, or `unknown`, a non-empty
  `source`, and an optional non-empty `argument`. Malformed trust metadata
  emits `INTENT_GRAPH_TRUST_INVALID` and makes the graph non-executable because
  runtime trust sinks must not infer missing or malformed trust.
- Graph `Context` nodes are runtime source bindings, not executable operations.
  They must carry valid context source data: `data.source` and
  `data.expression` must be non-empty strings, `data.args`, `data.argKinds`, and
  `data.argSpans` must be objects, and every `data.argSpans` value must be a
  valid source span. Malformed context source data emits
  `INTENT_GRAPH_CONTEXT_INVALID` and makes the graph non-executable because
  runtimes must not infer source identity, argument provenance, or executable
  behavior from incomplete context records.
- Graph `Goal` nodes are the next Phase 2 static-model milestone. Goal node
  data must carry `title` as `null` or a non-empty string, `parameters` as an
  array of valid parameter records with non-empty `name` and `type` strings and
  valid spans, `outputType` as `null` or a non-empty string, and
  `outputTypeSpan` as `null` or a valid span. Malformed Goal node payloads emit
  `INTENT_GRAPH_GOAL_INVALID` and make graph output non-executable because
  runtimes must not infer goal titles, inputs, output types, or provenance.
- Graph `Input` nodes are runtime data ports. Goal inputs and step inputs must
  carry `data.scope` as either `goal` or `step` and a non-empty `data.type`.
  Step input nodes must also be attached to their owning step through the
  existing graph edge contracts, including the required `requires` edge to that
  step and the incoming `data` edge from a goal input or earlier producing
  step. Malformed input payloads emit `INTENT_GRAPH_INPUT_INVALID` and make the
  graph non-executable because runtimes must not infer missing type, scope, or
  step ownership.
- Graph `Step` node data must carry arrays for `inputs`, `effects`, `requirements`,
  `checkpoints`, `approvals`, `timeouts`, and `retries`. Each input must be a
  valid parameter record with non-empty `name` and `type` strings and a valid
  `span`. `outputType` may be `null` or a non-empty string, and
  `outputTypeSpan` may be `null` or a valid span. Malformed Step node payloads
  emit `INTENT_GRAPH_STEP_INVALID` and make graph output non-executable
  because runtimes must not infer executable inputs, side effects, gates,
  checkpoints, approvals, timeouts, retries, or output types.
- Graph `Effect` nodes are runtime adapter invocations. They must carry valid
  adapter data: `data.family` and `data.action` must be non-empty strings,
  `data.args`, `data.argKinds`, and `data.argSpans` must be objects, every
  `data.argSpans` value must be a valid source span, and
  `data.approvalRequired` must be a boolean. Malformed effect adapter data
  emits `INTENT_GRAPH_EFFECT_INVALID` and makes the graph non-executable
  because runtimes must not infer an adapter, action, argument provenance, or
  approval requirement.
- Graph `Check` nodes are runtime verification gates, not executable steps.
  They must carry a non-empty `data.requirement`; optional `data.scope` must be
  either `goal` or `step`. Step-scoped checks must also carry non-empty
  `data.ownerStep` and `data.assertion`. When a check carries `data.effect`,
  that nested effect must include non-empty `family` and `action` strings,
  object `args`, `argKinds`, and `argSpans` maps, and valid source spans for
  every `argSpans` value. Malformed check payload data emits
  `INTENT_GRAPH_CHECK_INVALID` and makes the graph non-executable; malformed
  check effect trust metadata remains `INTENT_GRAPH_TRUST_INVALID`.
- Graph `Capability` nodes are runtime policy inputs. They must carry valid
  approval-policy data: `data.family` must be non-empty,
  `data.approvalPolicy` must be either `none` or `required`, and `data.grants`
  must be an array. Malformed capability policy data emits
  `INTENT_GRAPH_CAPABILITY_INVALID` and makes the graph non-executable because
  runtime authorization and approval enforcement must not infer missing policy.
- Graph `Approval` nodes are runtime approval gates. They must carry valid step
  gate data: `data.approval` must be non-empty and `data.ownerStep` must be
  non-empty. Malformed approval gate data emits `INTENT_GRAPH_APPROVAL_INVALID`
  and makes the graph non-executable because runtimes must not infer approval
  identity or step ownership.
- Graph `Checkpoint` nodes are runtime resumability inputs. They must carry
  valid step checkpoint data: `data.checkpoint` must be non-empty and
  `data.ownerStep` must be non-empty. Malformed checkpoint data emits
  `INTENT_GRAPH_CHECKPOINT_INVALID` and makes the graph non-executable because
  runtimes must not infer checkpoint identity or step ownership.
- Graph `Policy` nodes are runtime execution-policy inputs. They must carry
  valid step execution data: `data.policyKind` must be either `timeout` or
  `retry`, `data.policy` must be non-empty, and `data.ownerStep` must be
  non-empty. Malformed step policy data emits `INTENT_GRAPH_POLICY_INVALID`
  and makes the graph non-executable because runtimes must not infer timeout or
  retry behavior.
- Graph `Memory` nodes are runtime lifecycle inputs. They must carry raw
  `data.retention` as an array and structured `data.retentionRules` as a
  non-empty array. Each retention rule must include non-empty `raw`,
  `subject.raw`, and `until.raw` strings, and `until.raw` must be one of
  `goal_complete`, `goal.completed`, or a bounded duration such as `30d`.
  Malformed memory lifecycle data emits `INTENT_GRAPH_MEMORY_INVALID` and makes
  the graph non-executable because runtime retention cannot be inferred.
- A graph with duplicate node ids, unsupported kinds, unresolved edge endpoints,
  cycles, missing authorization or approval edges, or invalid completion gates is
  malformed and must be rejected before execution.
- CLI output should validate against the matching schema file when schema
  validation is wired into tests or CI.

Useful contract checks:

```shell
node intent/bin/intent.mjs parse intent/fixtures/valid_code_change.intent
node intent/bin/intent.mjs check intent/fixtures/valid_code_change.intent
node intent/bin/intent.mjs graph intent/fixtures/valid_code_change.intent
node --test intent/test/*.test.mjs
```

## Why It Exists

Agents do not only execute code. They interpret intent, gather context, call tools, make assumptions, recover from errors, and decide when they need human input.

Those behaviors are usually hidden inside prompts, frameworks, logs, or orchestration glue. Intent makes them part of the program.

## Language Primitives

- `goal`: the outcome the agent is trying to reach.
- `context`: bounded sources of truth such as files, tickets, docs, logs, chats, or prior runs.
- `capability`: explicit permissions for files, shell commands, network calls, secrets, deploys, and external tools.
- `plan`: resumable steps with stable inputs and outputs.
- `effect`: typed side effects such as `FileWrite`, `ShellExec`, `HttpCall`, `GitCommit`, or `Deploy`.
- `memory`: persisted state that must be scoped, retained with an explicit
  `retain ... until ...` lifecycle, inspectable, and erasable.
- `uncertainty`: first-class assumptions, confidence, and human-decision points.
- `verify`: tests, assertions, screenshots, policy checks, and runtime checks.
- `rollback`: compensating actions for risky or irreversible effects.
- `provenance`: traceability from output back to commands, files, docs, and assumptions.

## Design Principles

1. Goals are explicit.
2. Permissions are typed.
3. Side effects are visible.
4. Plans are resumable.
5. Verification is mandatory.
6. Assumptions are declared.
7. Human approval is a language feature, not a comment.
8. Memory has scope and lifecycle.
9. Failure is recoverable by default.
10. Every result has provenance.

## Runtime Shape

Intent programs could compile into execution graphs that agent runtimes can inspect before running. A runtime would be able to answer:

- What is this agent allowed to touch?
- What tools can it call?
- What state can it remember?
- Which steps are reversible?
- Which checks must pass before completion?
- Which actions require human approval?
- Why did it make this decision?

In that world, agents become less like opaque chat loops and more like auditable, typed collaborators.

## Example: Research Task

```intent
goal "compare model providers" {
  context web(domains: ["openai.com", "anthropic.com", "google.com"])
  capability web(read)
  budget time: 20m

  plan {
    collect official_docs
    extract pricing, limits, model_families
    compare on ["latency", "cost", "context", "tool_use"]
    cite sources
  }

  verify {
    require sources >= 3
    require no_uncited_claims
  }
}
```

## Example: Code Change

```intent
goal "add csv export" {
  context repo("./")
  capability file(read, write)
  capability shell(run: ["npm test", "npm run typecheck"])

  plan {
    inspect feature_boundary
    implement smallest_change
    update tests
    verify with ["npm test", "npm run typecheck"]
  }

  invariant {
    no_any_types
    no_unrelated_refactors
  }
}
```

## Open Questions

- Should Intent be a standalone language, a DSL, or an intermediate representation?
- Should it target existing runtimes such as Temporal, Kubernetes, GitHub Actions, or custom agent sandboxes?
- How strict should the type system be around uncertainty and side effects?
- Can prompts be compiled into Intent safely?
- What does package management mean when capabilities are part of the dependency graph?

## First Prototype

The smallest useful prototype would include:

1. A parser for `goal`, `context`, `capability`, `plan`, `verify`, and `invariant`.
2. A static checker that rejects undeclared side effects.
3. A runtime that executes steps through tool adapters.
4. A checkpoint store for resumability.
5. A verification gate that must pass before a goal can complete.

The language should begin as a constraint system around agents, then grow toward a full programming model.
