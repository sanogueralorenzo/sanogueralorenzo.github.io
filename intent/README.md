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
    deny secret_write
    deny unrelated_file_write
    require external_calls_explained
  }
}
```

## Prototype CLI

The Phase 2 static model starts as a dependency-free Node CLI:

```shell
node intent/bin/intent.mjs parse intent/fixtures/valid_code_change.intent
node intent/bin/intent.mjs check intent/fixtures/valid_code_change.intent
node intent/bin/intent.mjs graph intent/fixtures/valid_code_change.intent
node intent/bin/intent.mjs graph intent/examples/code_change.intent
node intent/bin/intent.mjs contracts
node --test intent/test/*.test.mjs
```

The first implementation requires exactly one leading package declaration,
allows imports only before type or goal declarations, parses goal blocks,
preserves source spans, checks for missing verification, undeclared effects,
capability coverage, verification shell grants, and memory retention
lifecycles, accepts `require` and `deny` invariants, and emits versioned JSON
contracts for downstream tools.

## JSON Output Contracts

Every successful command writes formatted JSON to stdout and includes a stable
`schema_version` field:

- `parse`: emits `intent.ast.v0`, the parsed source model with package, type,
  import, goal, block, step, effect, and span data.
- `check`: emits `intent.check.v0`, a diagnostic envelope with `ok` and
  `diagnostics`.
- `graph`: emits `intent.graph.v0`, an execution graph envelope with
  `ast_schema_version`, `source`, `package`, `ok`, `diagnostics`, `nodes`, and
  `edges`.
- `contracts`: emits `intent.effect-contracts.v0`, the effect adapter contract
  registry used to normalize effect calls before checking and graph emission.

The schema files for the contract milestone are expected at these paths:

- `intent/schemas/intent.ast.v0.schema.json`
- `intent/schemas/intent.check.v0.schema.json`
- `intent/schemas/intent.graph.v0.schema.json`
- `intent/schemas/intent.effect-contracts.v0.schema.json`

Schema names and `schema_version` values must move together. A breaking payload
change requires a new schema version and a new schema file instead of silently
changing an existing contract.

Validation expectations:

- Valid fixtures and executable examples must parse, check with `ok: true`, and
  emit graph JSON with `ok: true`.
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
  emit `INTENT_GRAPH_SCHEMA_INVALID`.
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
  validation. Later validation ignores malformed records instead of inferring
  missing fields from them.
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
- Runtime graph typed edge span matches compare the full span, including file,
  line, column, and zero-based UTF-8 byte offsets.
- Runtime graph `plans` edges have a constrained role contract. A `plans` edge
  is valid only from a `Goal` node to a `Step` node. Unsupported `plans`
  endpoint roles emit `INTENT_GRAPH_PLAN_INVALID` and make graph output
  non-executable. This generic role diagnostic is separate from step ownership
  coverage: missing, duplicate, or wrong-owner incoming `plans` edges for a
  `Step` remain `INTENT_GRAPH_STEP_PLAN_INVALID`; malformed `Goal` payloads
  remain `INTENT_GRAPH_GOAL_INVALID`; and malformed `Step` payloads remain
  `INTENT_GRAPH_STEP_INVALID`. Constraining the generic role prevents plan
  topology from being replayed from ambiguous runtime-control edges while
  preserving step-specific ownership diagnostics.
- Runtime graph `declares` edges have a constrained role contract. A
  `declares` edge is valid only from `Type` to `Goal` for type availability or
  from `Goal` to `Memory` for goal-owned memory. Unsupported `declares`
  endpoint roles emit `INTENT_GRAPH_DECLARE_INVALID` and make graph output
  non-executable. This role diagnostic is separate from ownership-specific
  diagnostics: missing, duplicate, or wrong coverage for Type availability
  remains `INTENT_GRAPH_TYPE_DECLARE_INVALID`; missing, duplicate, or wrong
  owning Goal for Memory remains `INTENT_GRAPH_MEMORY_DECLARE_INVALID`; and
  malformed node payloads remain `INTENT_GRAPH_TYPE_INVALID` or
  `INTENT_GRAPH_MEMORY_INVALID`. Constraining the generic role prevents
  `declares` from becoming an ambiguous catch-all edge during runtime replay.
- Runtime graph `authorizes` edges have a constrained role contract. An
  `authorizes` edge is valid only from `Capability` to `Goal` for capability
  ownership, or from `Capability` to an `Effect`, `Check`, or `Context` node
  for runtime authorization. `authorizes` edges to unsupported target roles,
  and non-Capability `authorizes` edges, emit
  `INTENT_GRAPH_AUTHORIZE_INVALID` and make graph output non-executable. This
  generic role diagnostic is separate from source- and coverage-specific
  diagnostics: missing, duplicate, or wrong owning-Goal capability ownership
  remains `INTENT_GRAPH_CAPABILITY_AUTHORIZES_INVALID`; missing or
  non-Capability incoming authorization for `Effect`, verification `Check`, or
  external `Context` remains `INTENT_GRAPH_AUTHORIZATION_INVALID`; Capability
  authorization edges whose grant records do not cover the target family,
  action, and constrained arguments emit
  `INTENT_GRAPH_AUTHORIZATION_GRANT_INVALID`; and malformed node payloads keep
  their existing node diagnostics. Constraining the generic role prevents
  `authorizes` from becoming an ambiguous catch-all edge during runtime replay
  while preserving target-specific authorization diagnostics.
- Runtime graph `requests` edges have a constrained target-role contract. A
  `requests` edge may target only an `Effect` node because `requests`
  represents a step asking the runtime to execute an effect/tool adapter.
  `requests` edges to unsupported target roles emit
  `INTENT_GRAPH_REQUEST_INVALID` and make graph output non-executable. This
  generic target-role diagnostic is separate from effect ownership coverage:
  missing requests edges for an `Effect`, duplicate requests edges, or incoming
  requests not from the owning `Step` remain
  `INTENT_GRAPH_EFFECT_REQUEST_INVALID`; malformed `Effect` payloads remain
  `INTENT_GRAPH_EFFECT_INVALID`; and malformed edge payloads remain
  `INTENT_GRAPH_EDGE_PAYLOAD_INVALID` when applicable. Constraining the generic
  target role prevents `requests` from becoming an ambiguous runtime-control
  edge while preserving effect-specific ownership diagnostics.
- Runtime graph `gates` and `verifies` edges have constrained role contracts.
  A `gates` edge is valid only from a `Check` node to a `Goal` node.
  Unsupported `gates` endpoint roles emit `INTENT_GRAPH_GATE_INVALID` and make
  graph output non-executable. A `verifies` edge is valid only from a `Check`
  node to a `Completion` node. Unsupported `verifies` endpoint roles emit
  `INTENT_GRAPH_VERIFY_INVALID` and make graph output non-executable. These
  generic role diagnostics are separate from check coverage diagnostics:
  missing, duplicate, or wrong-owner goal gates, missing goal-scoped completion
  verifies, and step-scoped checks with otherwise role-valid verifies edges
  remain `INTENT_GRAPH_CHECK_GATE_INVALID`; malformed `Check` payloads remain
  `INTENT_GRAPH_CHECK_INVALID`; and malformed `Completion` payloads remain
  `INTENT_GRAPH_COMPLETION_INVALID`. Role-valid `gates` and `verifies` edges
  must also carry non-empty `data.requirement`, valid `data.scope`,
  `sourceSpan`, and `targetSpan` values that match the source `Check`, owning
  `Goal`, and owning `Completion`; malformed payloads emit
  `INTENT_GRAPH_EDGE_PAYLOAD_INVALID`, and typed endpoint mismatches emit
  `INTENT_GRAPH_TYPED_EDGE_INVALID`. Constraining the generic roles prevents
  verification edges from becoming ambiguous runtime-control edges while
  preserving check-specific gate coverage diagnostics.
- Runtime graph `completes` and `produces` edges have constrained completion
  delivery role contracts. A `completes` edge is valid only from a `Goal` node
  to a `Completion` node. Unsupported `completes` endpoint roles emit
  `INTENT_GRAPH_COMPLETE_INVALID` and make graph output non-executable. A
  `produces` edge is valid only from a `Step` node to a `Completion` node.
  Unsupported `produces` endpoint roles emit `INTENT_GRAPH_PRODUCE_INVALID` and
  make graph output non-executable. These generic role diagnostics are separate
  from `INTENT_GRAPH_COMPLETION_INVALID`,
  `INTENT_GRAPH_GOAL_COMPLETION_INVALID`, and
  `INTENT_GRAPH_EDGE_PAYLOAD_INVALID`. Constraining the generic completion
  delivery roles prevents ambiguous completion replay while preserving
  completion-specific diagnostics.
- Runtime graph data and topology edges have constrained role contracts.
  `data` is valid only from a goal-scoped `Input` or `Step` producer to a
  step-scoped `Input`; unsupported endpoint roles emit
  `INTENT_GRAPH_DATA_ROLE_INVALID`. `supplies` is valid only as goal-scoped
  `Input` to `Goal`; unsupported endpoint roles emit
  `INTENT_GRAPH_SUPPLY_INVALID`. `informs` is valid only as `Context` to
  `Goal`; unsupported endpoint roles emit `INTENT_GRAPH_INFORM_INVALID`.
  `precedes` is valid only as `Step` to `Step`; unsupported endpoint roles
  emit `INTENT_GRAPH_PRECEDE_INVALID`. These generic role diagnostics are
  separate from `INTENT_GRAPH_DATA_INVALID`,
  `INTENT_GRAPH_INPUT_SUPPLY_INVALID`,
  `INTENT_GRAPH_CONTEXT_INFORMS_INVALID`,
  `INTENT_GRAPH_STEP_SEQUENCE_INVALID`,
  `INTENT_GRAPH_EDGE_PAYLOAD_INVALID`,
  `INTENT_GRAPH_TYPED_EDGE_INVALID`, and malformed node payload diagnostics.
  Runtime `data` and `supplies` edge payloads must also match endpoint names,
  endpoint types, ownership, and source/target spans. This prevents
  topology/data edges from being replayed as ambiguous runtime-control edges
  while preserving ownership, sequencing, typed-binding, and payload
  diagnostics.
- Runtime graph memory access edges have constrained provenance contracts.
  `writes` is valid only as `Step` to `Memory`, while `reads` and `cites` are
  valid only as `Memory` to `Step`. Each edge carries `data.access`,
  `data.memory`, nullable `data.key`, `data.target`, optional
  `data.retentionRef`, and source/target spans. Keyed targets must match a
  retained subject or explicit key on the referenced `Memory` node.
  Unsupported endpoint roles emit `INTENT_GRAPH_MEMORY_ACCESS_INVALID`, and
  malformed payloads emit `INTENT_GRAPH_EDGE_PAYLOAD_INVALID`. Keyed target
  mismatches emit `INTENT_GRAPH_MEMORY_TARGET_INVALID`.
- Completion citation policy is enforced by the checker and graph contract.
  `require all_outputs_cited`, `require memory_provenance_complete`, or
  `deny uncited_external_claim` requires the final completion-producing step to
  declare at least one `memory cite ...` statement. Missing citation coverage
  emits `INTENT_PROVENANCE_MISSING`. Completion node `data.provenance` records
  the triggering requirements, invariants, and final-step citations; malformed
  provenance payloads or required provenance with no citations emit
  `INTENT_GRAPH_COMPLETION_INVALID`.
- Completion checkpoint policy is enforced by the checker and graph contract.
  `require final_state_checkpointed`, `require checkpointed_final_state`, or
  `deny uncheckpointed_irreversible_effect` requires the final
  completion-producing step to declare at least one `checkpoint ...` statement.
  Missing checkpoint coverage emits `INTENT_CHECKPOINT_MISSING`. Completion
  node `data.checkpoint` records the triggering requirements, invariants, and
  final-step checkpoints; malformed checkpoint payloads or required checkpoint
  metadata with no checkpoint records emit `INTENT_GRAPH_COMPLETION_INVALID`.
- Runtime graph `produces` and `requires` edge payloads are typed contracts.
  The role-valid `produces` edge from the final executable `Step` to
  `Completion` must carry non-empty `type` plus valid `sourceSpan` and
  `targetSpan` values, and those values must match the source `Step` output
  type/span and the target `Completion` output type/span when declared, or the
  target `Completion` span when no output type is declared. `requires`
  is valid only as `Input` to `Step` for step inputs or step-scoped `Check` to
  `Step` for step requirements. Step-input `requires` edges must match the source input
  name, type, owning step, and span; step-requirement `requires` edges must
  match the source requirement and owning step. Malformed payloads emit
  `INTENT_GRAPH_EDGE_PAYLOAD_INVALID`, typed endpoint mismatches emit
  `INTENT_GRAPH_TYPED_EDGE_INVALID`, unsupported endpoint roles emit
  `INTENT_GRAPH_PRODUCE_INVALID` or `INTENT_GRAPH_REQUIRE_INVALID`, wrong
  completion counts remain `INTENT_GRAPH_COMPLETION_INVALID`, wrong final-step
  sequencing remains `INTENT_GRAPH_STEP_SEQUENCE_INVALID`, and missing
  attachment coverage remains `INTENT_GRAPH_STEP_ATTACHMENT_INVALID`.
- Runtime graph goal-input supply edges are typed contracts. Every goal-scoped
  `Input` node must have exactly one outgoing role-valid `supplies` edge to its
  owning `Goal`, and that edge must carry non-empty `data.parameter`,
  non-empty `data.type`, and valid `sourceSpan` and `targetSpan` values that
  match the source input name, type, owner goal, and parameter span. Missing or
  extra role-valid goal-input `supplies` edges emit
  `INTENT_GRAPH_INPUT_SUPPLY_INVALID` and make graph output non-executable;
  unsupported `supplies` endpoint roles emit `INTENT_GRAPH_SUPPLY_INVALID`;
  malformed edge payloads emit `INTENT_GRAPH_EDGE_PAYLOAD_INVALID`; typed
  endpoint mismatches emit `INTENT_GRAPH_TYPED_EDGE_INVALID`; malformed `Input`
  node data remains `INTENT_GRAPH_INPUT_INVALID`, and missing step input data or
  `requires` edges remain `INTENT_GRAPH_INPUT_UNBOUND` or
  `INTENT_GRAPH_STEP_ATTACHMENT_INVALID`. Step-scoped `Input` nodes remain
  covered by the existing `data` and `requires` edge contracts and must not rely
  on `supplies`. This makes goal parameter ownership explicit in the runtime
  graph instead of relying on id strings alone.
- Runtime graph step attachment edge payloads are typed contracts. `approves` is
  valid only as `Approval` to `Step` or `Approval` to
  `Effect`, and unsupported endpoint roles emit `INTENT_GRAPH_APPROVE_INVALID`.
  `checkpoints` is valid only as `Step` to `Checkpoint`, and unsupported endpoint
  roles emit `INTENT_GRAPH_CHECKPOINT_EDGE_INVALID`. `timeouts` and `retries`
  are valid only as `Policy` to `Step`, and unsupported endpoint roles emit
  `INTENT_GRAPH_POLICY_EDGE_INVALID`. Step-scoped `Approval` to `Step`
  `approves` edges and `Approval` to `Effect` `approves` edges must carry
  non-empty `data.approval` matching the source `Approval` node, and must stay
  within the owning step for effect approvals. Step-scoped `Policy` to `Step`
  `timeouts` and `retries` edges must carry non-empty `data.policy` matching the
  source `Policy` node and edge kind. `Step` to `Checkpoint` `checkpoints`
  edges must carry non-empty `data.checkpoint` matching the target `Checkpoint`
  node and owning step. Malformed step attachment edge payloads emit
  `INTENT_GRAPH_EDGE_PAYLOAD_INVALID`, typed attachment mismatches emit
  `INTENT_GRAPH_TYPED_EDGE_INVALID`, and make graph output non-executable;
  missing attachment coverage remains
  `INTENT_GRAPH_STEP_ATTACHMENT_INVALID`. These generic role diagnostics are
  separate from `INTENT_GRAPH_STEP_ATTACHMENT_INVALID`,
  `INTENT_GRAPH_EDGE_PAYLOAD_INVALID`, `INTENT_GRAPH_TYPED_EDGE_INVALID`, and
  malformed node payload diagnostics such as `INTENT_GRAPH_INPUT_INVALID`,
  `INTENT_GRAPH_CHECK_INVALID`, `INTENT_GRAPH_APPROVAL_INVALID`,
  `INTENT_GRAPH_CHECKPOINT_INVALID`, and `INTENT_GRAPH_POLICY_INVALID`. This
  prevents step attachment edges from being replayed as ambiguous runtime-control
  edges while preserving attachment coverage and payload diagnostics.
- Runtime graph check gate edges are typed contracts. Every `Check` node is a
  runtime gate and must have exactly one outgoing `gates` edge to its owning
  `Goal`. Goal-scoped verification `Check` nodes must also have exactly one
  outgoing `verifies` edge to the owning `Completion` node. Step-scoped
  requirement `Check` nodes must have no `verifies` edges; they attach to their
  owning step with the existing `requires` edge contract and gate the owning
  goal with `gates`. Role-valid `gates` and `verifies` edges must carry
  non-empty `data.requirement`, valid `data.scope`, and valid source/target
  spans matching the source check and owning target. Missing, duplicate, or
  wrong-owner goal gates, missing goal-scoped completion verifies, and
  step-scoped checks with otherwise role-valid verifies edges emit
  `INTENT_GRAPH_CHECK_GATE_INVALID` and make graph output non-executable.
  Malformed edge payloads emit `INTENT_GRAPH_EDGE_PAYLOAD_INVALID`, typed
  endpoint mismatches emit `INTENT_GRAPH_TYPED_EDGE_INVALID`, unsupported
  `gates` and `verifies` endpoint roles instead emit `INTENT_GRAPH_GATE_INVALID`
  or `INTENT_GRAPH_VERIFY_INVALID`, malformed `Check` node data remains
  `INTENT_GRAPH_CHECK_INVALID`, malformed `Completion` node data remains
  `INTENT_GRAPH_COMPLETION_INVALID`, and missing step attachment edges remain
  `INTENT_GRAPH_STEP_ATTACHMENT_INVALID`.
- Executable graph node spans must include a string `file` and object `start`
  and `end` positions with positive integer `line` and `column` values plus
  zero-based UTF-8 byte `offset` values.
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
- Runtime context source authorization edge contracts are part of graph
  validation. Runtime `Context` nodes with `data.source` equal to `web` or
  `documents` carry `contractId` and `contractArguments` records for the
  selected read contract and must have one or more incoming `authorizes` edges
  from `Capability` nodes. Those authorization edges carry the same contract id
  and matched grant records. `repo` Context nodes remain local/trusted and do
  not require graph authorization edges. Malformed, missing, or non-Capability
  authorization edges for external context sources emit
  `INTENT_GRAPH_AUTHORIZATION_INVALID`; stale grant or edge contract references
  emit `INTENT_GRAPH_AUTHORIZATION_GRANT_INVALID`; malformed Context node data
  remains `INTENT_GRAPH_CONTEXT_INVALID`; and malformed trust metadata remains
  `INTENT_GRAPH_TRUST_INVALID`. This makes external context source access
  explicit in the runtime graph instead of relying only on source checker
  results.
- Runtime context ownership edge contracts are the next Phase 2 static-model
  milestone. Every `Context` node must have exactly one outgoing `informs` edge
  to its owning `Goal`. This ownership edge is separate from external context
  authorization: `web` and `documents` Context nodes still require incoming
  Capability `authorizes` edges, while `repo` Context nodes do not. Missing or
  extra role-valid context `informs` edges emit
  `INTENT_GRAPH_CONTEXT_INFORMS_INVALID` and make graph output non-executable;
  unsupported `informs` endpoint roles emit `INTENT_GRAPH_INFORM_INVALID`;
  malformed Context node data remains
  `INTENT_GRAPH_CONTEXT_INVALID`, malformed trust metadata remains
  `INTENT_GRAPH_TRUST_INVALID`, and external-context authorization failures
  remain `INTENT_GRAPH_AUTHORIZATION_INVALID`. This makes context ownership
  explicit in the runtime graph instead of relying on id strings alone.
- Graph `Type` nodes are runtime type metadata. Type node
  data must carry `definition` as `null` or a non-empty string representing the
  declared structural or alias body. Malformed Type node payloads emit
  `INTENT_GRAPH_TYPE_INVALID` and make graph output non-executable because
  runtimes must not infer structural or alias type bodies.
- Runtime type availability edge contracts are the next Phase 2 static-model
  milestone. `Type` nodes are package/file-scoped runtime type metadata visible
  to every `Goal` in the graph. Every `Type` node must have exactly one
  outgoing `declares` edge to each `Goal` node. Missing, duplicate, or wrong
  `Goal` coverage from a `Type` node emits
  `INTENT_GRAPH_TYPE_DECLARE_INVALID` and make graph output non-executable;
  malformed Type node data remains `INTENT_GRAPH_TYPE_INVALID`, and unsupported
  `declares` endpoint roles remain `INTENT_GRAPH_DECLARE_INVALID`. This makes
  type availability explicit for runtime validation and graph replay instead of
  relying only on package/global lookup.
- Graph `Goal` nodes carry runtime requested-work metadata. Goal node data must
  carry `title` as `null` or a non-empty string, `parameters` as an array of
  valid parameter records with non-empty `name` and `type` strings and valid
  spans, `outputType` as `null` or a non-empty string, and `outputTypeSpan` as
  `null` only when `outputType` is `null` or a valid span when `outputType` is
  non-empty. Malformed Goal node payloads emit `INTENT_GRAPH_GOAL_INVALID` and
  make graph output non-executable because runtimes must not infer goal titles,
  inputs, output types, or provenance.
- Graph `Input` nodes are runtime data ports. Goal inputs and step inputs must
  carry `data.scope` as either `goal` or `step` and a non-empty `data.type`.
  Goal-scoped input nodes must supply their owning goal through exactly one
  outgoing `supplies` edge.
  Step input nodes must also be attached to their owning step through the
  existing graph edge contracts, including the required `requires` edge to that
  step and the incoming `data` edge from a goal input or earlier producing
  step. Malformed input payloads emit `INTENT_GRAPH_INPUT_INVALID` and make the
  graph non-executable because runtimes must not infer missing type, scope, or
  step ownership.
- Graph `Step` node data must carry arrays for `inputs`, `effects`,
  `requirements`, `checkpoints`, `approvals`, `timeouts`, `retries`, and
  `memoryAccesses`. Each input must be a valid parameter record with non-empty
  `name` and `type` strings and a valid `span`; every memory access target must
  be non-empty. `outputType` may be `null` or a non-empty string;
  `outputTypeSpan` must be `null` when `outputType` is `null` and a valid span
  when `outputType` is non-empty. Malformed Step node payloads emit
  `INTENT_GRAPH_STEP_INVALID` and make graph output non-executable because
  runtimes must not infer executable inputs, side effects, gates, checkpoints,
  approvals, timeouts, retries, memory accesses, or output types.
- Graph `Completion` nodes carry runtime completion metadata. Completion node
  data must carry `outputType` as `null` or a non-empty string and
  `outputTypeSpan` as `null` when `outputType` is `null` or a valid span when
  `outputType` is non-empty. It must also carry `provenance` with citation
  requirements, invariants, and final-step memory citations, plus `checkpoint`
  with final-state checkpoint requirements, invariants, and final-step
  checkpoints. Malformed Completion node payloads emit
  `INTENT_GRAPH_COMPLETION_INVALID` and make graph output non-executable. This
  runtime payload contract is separate from
  the existing
  completion-edge contract, which still requires `completes`, `produces`,
  `verifies`, and invariant `guards` edges.
- Graph `Invariant` nodes are the next Phase 2 static-model milestone.
  Invariant node data must carry `assertion` as `Require` or `Deny` and
  `invariant` as a non-empty string. Malformed Invariant node payloads emit
  `INTENT_GRAPH_INVARIANT_INVALID` and make graph output non-executable because
  runtimes must not infer always-on rule polarity or identity. This runtime
  payload contract is separate from invariant ownership and guard coverage.
  `constrains` is valid only as `Invariant` to `Goal`; unsupported endpoint
  roles emit `INTENT_GRAPH_CONSTRAIN_INVALID`. `guards` is valid only from
  `Invariant` to `Completion`, `Effect`, `Checkpoint`, `Policy`, or
  step-scoped `Check`; unsupported endpoint roles emit
  `INTENT_GRAPH_GUARD_ROLE_INVALID`. These generic role diagnostics are
  separate from `INTENT_GRAPH_INVARIANT_CONSTRAINT_INVALID`,
  `INTENT_GRAPH_GUARD_INVALID`, `INTENT_GRAPH_INVARIANT_INVALID`, and node
  payload diagnostics. Each Invariant node must have exactly one outgoing
  role-valid `constrains` edge to its owning `Goal`; malformed, missing, or
  extra invariant ownership edges emit
  `INTENT_GRAPH_INVARIANT_CONSTRAINT_INVALID`, while missing role-valid
  `guards` edges still emit `INTENT_GRAPH_GUARD_INVALID`. This prevents
  invariant edges from being replayed as ambiguous runtime-control edges while
  preserving invariant-specific coverage diagnostics.
- Graph `Effect` nodes are runtime adapter invocations. They must carry valid
  adapter data: `data.family` and `data.action` must be non-empty strings,
  `data.args`, `data.argKinds`, and `data.argSpans` must be objects, every
  `data.argSpans` value must be a valid source span, and
  `data.approvalRequired` must be a boolean. Malformed effect adapter data
  emits `INTENT_GRAPH_EFFECT_INVALID` and makes the graph non-executable
  because runtimes must not infer an adapter, action, argument provenance, or
  approval requirement.
- Effect adapter family, action, constrained arguments, aliases, context-source
  read access, and trust-sensitive sinks are normalized through the v0 effect
  contract registry before graph emission. Effect nodes, verification-effect
  payloads, and external `Context` nodes carry a stable `contractId` plus
  `contractArguments` references so runtimes can verify which contract and
  source argument aliases were selected. Authorization edges also carry the
  selected contract id and matched grant argument records. Structured
  capability grants that cover known v0 contracts carry `contractId` and
  `contractArgument` so stale grant references are rejected during graph
  validation.
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
  must be an array of structured grant records. Each grant must carry non-empty
  `action`, `key`, and `raw` strings, a string `value`, and a valid source
  `span`. Malformed capability policy data emits `INTENT_GRAPH_CAPABILITY_INVALID`
  and makes the graph non-executable because runtime authorization and approval
  enforcement must not infer missing policy.
- Runtime capability ownership edge contracts are the next Phase 2 static-model
  milestone. Every graph `Capability` node must have exactly one outgoing
  `authorizes` edge whose target is its owning `Goal`. Malformed, missing,
  duplicate, or wrong-Goal capability ownership `authorizes` edges emit
  `INTENT_GRAPH_CAPABILITY_AUTHORIZES_INVALID` and make graph output
  non-executable; malformed Capability node data remains
  `INTENT_GRAPH_CAPABILITY_INVALID`. This ownership edge is separate from
  runtime target authorization: Capability `authorizes` edges to `Effect`,
  `Check`, and external `Context` targets must be backed by matching grant
  records, unsupported target roles or non-Capability authorization edges emit
  `INTENT_GRAPH_AUTHORIZE_INVALID`, malformed or missing target authorization
  still emits `INTENT_GRAPH_AUTHORIZATION_INVALID`, and grant mismatches emit
  `INTENT_GRAPH_AUTHORIZATION_GRANT_INVALID`.
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
- Runtime memory ownership edge contracts are the next Phase 2 static-model
  milestone. Every graph `Memory` node owned by a goal must have exactly one
  incoming `declares` edge from its owning `Goal`. Missing, duplicate, or
  wrong-Goal memory ownership `declares` edges emit
  `INTENT_GRAPH_MEMORY_DECLARE_INVALID` and make graph output non-executable;
  malformed `Memory` node retention lifecycle data remains
  `INTENT_GRAPH_MEMORY_INVALID`, and unsupported `declares` endpoint roles
  remain `INTENT_GRAPH_DECLARE_INVALID`. This makes memory ownership explicit
  for runtime recovery and provenance instead of relying only on id strings.
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
