# Intent Static Model

Phase 2 turns the written language contract into a parsed, checked, and
machine-readable model. This note defines the first prototype shape only; it
does not try to settle the full language.

## AST Nodes

Every node carries a stable `id`, `kind`, `span`, and optional `name`.

- `PackageDecl`: package path for a source file.
- `ImportDecl`: imported package or symbol path.
- `GoalDecl`: root executable unit, spanned inputs, output, clauses, and body
  blocks.
- `ContextDecl`: named source of truth with structured call data, argument
  source spans, resource expression, freshness policy, access mode, trust
  zone/source, and optional capability coverage.
- `CapabilityDecl`: named permission grant with family, action, constraints,
  structured grant objects, and optional approval policy.
- `CapabilityGrant`: structured capability body grant with action path,
  constraints, raw text, and source span.
- `MemoryDecl`: scoped state or retained evidence with one or more retention
  lifecycle rules.
- `MemoryRetention`: structured `retain ... until ...` rule with retained
  subject, until condition, raw text, and source span.
- `PlanBlock`: ordered list of executable steps.
- `StepDecl`: spanned typed inputs, output, step-local requirements, step
  approval gates, step checkpoint statements, step policy statements, declared
  effects, checks, and body expression.
- `StepApproval`: structured `approval ...` step-body statement with raw
  approval text and source span.
- `StepCheckpoint`: structured `checkpoint ...` step-body statement with raw
  checkpoint text and source span.
- `StepPolicy`: structured `timeout ...` or `retry ...` step-body statement
  with policy kind, raw policy text, and source span.
- `VerifyBlock`: required or advisory completion checks.
- `InvariantBlock`: always-on rules evaluated across completion, effects,
  checkpoints, and step requirement checks.
- `EffectDecl`: reusable typed effect signature.
- `EffectCall`: parsed effect request with callee, arguments, argument source
  spans, source span, and raw text.
- `PolicyDecl`: trust, denial, approval, and flow rules.
- `TrustMark`: checker-owned trust metadata for a value, effect argument, graph
  node, or graph edge.
- `TypeDecl`: record, enum, alias, union, or generic type declaration.
- `Expr`: literals, names, field access, calls, lists, records, conditionals,
  matches, lets, returns, assignments, and effect requests.
- `TypeRef`: named, generic, record, list, map, optional, or union type use.

The prototype may parse unsupported nodes into `UnknownDecl` or `UnknownExpr`
only when it also emits a blocking diagnostic. Unsupported raw statements in a
goal body, outside known blocks such as `context`, `capability`, `memory`,
`plan`, `verify`, and `invariant`, emit `INTENT_UNSUPPORTED_SYNTAX` at the raw
statement span.

A syntactically valid source with package, imports, or type declarations but no
goal emits `INTENT_GOAL_MISSING` at the source span.

## Type Declarations And Built-ins

The first checker prototype supports file-local, top-level type declarations.
A declaration introduces a type name and may retain a raw definition string, but
the checker only binds the name in this milestone.

```intent
type ChangeRequest
type Finding = { path: Path, message: String }
type Patch = List<Path>
```

Rules:

- Type names must begin with an uppercase ASCII letter.
- Type declarations are visible to every goal in the same file.
- Type definitions are retained for graph/debug output, but record fields,
  aliases, enum cases, and generic parameters are not structurally checked yet.
- Imports do not contribute types in the first prototype.

Known built-in type names are:

- Values: `String`, `Bool`, `Int`, `Float`, and `Record`.
- Generic containers: `List` and `Map`.
- Intent model types: `Goal`, `Context`, `Capability`, `Effect`, and `Step`.
- Agent state types: `Evidence`, `Assumption`, `Decision`, `Verified`,
  `Checkpoint`, and `Provenance`.

Every uppercase type token in a goal input, goal output, step input, or step
output must resolve to one of those built-ins or a file-local type declaration.
Unresolved types emit `INTENT_TYPE_UNRESOLVED` on the declaration that used the
type.

## Source Locations

Source locations are required for every parsed node and diagnostic.

```json
{
  "file": "intent/examples/demo.intent",
  "start": { "line": 12, "column": 3, "offset": 184 },
  "end": { "line": 16, "column": 4, "offset": 322 }
}
```

Rules:

- Lines and columns are one-based for users.
- Offsets are zero-based UTF-8 byte offsets for tools.
- Spans include leading keywords and exclude trailing unrelated whitespace.
- Generated graph nodes keep `span` from the AST node that caused them.
- Goal header parameters and step header parameters keep `span` on the
  parameter object itself.
- Goal and step output type tokens keep `outputTypeSpan` alongside
  `outputType`; it is `null` when no output type is declared.
- Goal, Step, and Completion graph node data may carry the same
  `outputTypeSpan` so diagnostics can point at the exact declared output type
  instead of the wider node span.
- Graph node and edge data that embeds parameters keeps those parameter spans
  for provenance. Data dependency edges may carry `sourceSpan` and `targetSpan`
  so the producing and consuming parameters can both be traced precisely.
- Parsed call arguments keep `argSpans` alongside `args` and `argKinds`.
  `argSpans` maps each positional key such as `_0` or named key such as `path`,
  `command`, `url`, or `branch` to the source span for diagnostics and runtime
  provenance.
- Diagnostics for capability denial, context source denial, verification shell
  denial, and unsafe shell trust flows use the constrained argument's
  `argSpans` entry when that argument was parsed. They fall back to the wider
  call span only when the constrained argument has no parsed argument span.
- Structured capability grants keep `span` from the exact grant line that
  caused the grant object, not from the surrounding capability block.

## JSON Output Contracts

The CLI output contract is stdout JSON plus a process exit code. Every success
payload has a `schema_version` string. Schema versions are append-only
contracts: incompatible field, type, requiredness, or semantic changes require
a new version string and a new schema file.

Canonical schema files for this milestone:

- `intent/schemas/intent.ast.v0.schema.json`
- `intent/schemas/intent.check.v0.schema.json`
- `intent/schemas/intent.graph.v0.schema.json`

The parser, checker, and graph builder may add optional fields only when the
schema allows them and existing consumers can ignore them safely.

### Schema-Level Structural Strings

The AST, check, and graph schemas all reject empty structural strings before a
runtime, editor, or CI adapter interprets the payload. This keeps source
identity, declaration identity, diagnostics, and graph endpoints stable at the
contract boundary instead of leaving each consumer to guess which blanks are
meaningful.

For `intent.ast.v0`, schema-level non-empty strings include top-level `source`,
every span `file`, package names, type names, goal names, step names, parameter
names and parameter types when present, context source fields, trust source
labels, raw block names and headers, statement kinds,
capability family/name/constraint strings, capability actions when present,
grant `action`, `key`, and `raw` strings, memory scope/retention/body strings,
retention `raw` text, retention subject and `until` raw text when present,
effect names, effect families, effect actions when present, and effect
expressions.

For `intent.check.v0`, schema-level non-empty strings include diagnostic
`code`, `message`, every diagnostic span `file`, and optional diagnostic
metadata strings such as `name`, `type`, `step`, `parameter`, `memory`, `scope`,
`retention`, `effect`, `family`, `action`, `required_family`, `argument`,
`allowed`, and `declared_capabilities` entries when those fields are present.

Nullable descriptive fields remain nullable where the schema explicitly allows
them. Examples include goal titles, output types, output type spans, optional
capability and effect actions, memory names, type definitions, and parsed
retention subject or lifecycle parts. Null means "not declared"; an empty
string does not stand in for missing structure.

### Parse Output: `intent.ast.v0`

Command:

```shell
node intent/bin/intent.mjs parse <file.intent>
```

Success exits `0` and emits the parsed source model:

```json
{
  "schema_version": "intent.ast.v0",
  "source": "intent/fixtures/valid_code_change.intent",
  "package": {
    "kind": "Package",
    "name": "fixtures.code_change",
    "span": {
      "file": "intent/fixtures/valid_code_change.intent",
      "start": { "line": 1, "column": 1, "offset": 0 },
      "end": { "line": 1, "column": 29, "offset": 28 }
    }
  },
  "types": [],
  "goals": [],
  "span": {
    "file": "intent/fixtures/valid_code_change.intent",
    "start": { "line": 1, "column": 1, "offset": 0 },
    "end": { "line": 1, "column": 1, "offset": 0 }
  }
}
```

Required top-level fields are `schema_version`, `source`, `package`, `types`,
`goals`, and `span`. Parsed declarations preserve source order. Every parsed
node that maps to source text must carry a `span`.

Parse failures exit non-zero and emit the diagnostic envelope described by
`intent.check.v0` with `ok: false` and at least one `INTENT_PARSE_ERROR`
diagnostic.

### Check Output: `intent.check.v0`

Command:

```shell
node intent/bin/intent.mjs check <file.intent>
```

The checker always emits a diagnostic envelope:

```json
{
  "schema_version": "intent.check.v0",
  "ok": false,
  "diagnostics": [
    {
      "severity": "error",
      "code": "INTENT_VERIFY_MISSING",
      "message": "goal 'ship_checkout_fix' uses effects but has no verify block with require statements.",
      "span": {
        "file": "intent/examples/demo.intent",
        "start": { "line": 4, "column": 1, "offset": 64 },
        "end": { "line": 22, "column": 1, "offset": 420 }
      }
    }
  ]
}
```

Required top-level fields are `schema_version`, `ok`, and `diagnostics`.
`ok: true` requires an empty diagnostics array. Any error diagnostic requires
`ok: false` and exit code `1`. Usage errors, unknown commands, and unreadable
source files exit `2` and are reported on stderr.

### Graph Output: `intent.graph.v0`

Command:

```shell
node intent/bin/intent.mjs graph <file.intent>
```

Graph output is an execution graph envelope. This abbreviated example omits
most nodes and edges:

```json
{
  "schema_version": "intent.graph.v0",
  "ast_schema_version": "intent.ast.v0",
  "source": "intent/examples/demo.intent",
  "package": "examples.demo",
  "ok": true,
  "diagnostics": [],
  "nodes": [
    {
      "id": "goal:ship_checkout_fix",
      "kind": "Goal",
      "label": "ship_checkout_fix",
      "span": {
        "file": "intent/examples/demo.intent",
        "start": { "line": 4, "column": 1, "offset": 64 },
        "end": { "line": 22, "column": 1, "offset": 420 }
      },
      "data": {
        "title": null,
        "parameters": [],
        "outputType": "PullRequest",
        "outputTypeSpan": "loc.4"
      }
    },
    {
      "id": "goal:ship_checkout_fix:completion",
      "kind": "Completion",
      "label": "ship_checkout_fix",
      "span": {
        "file": "intent/examples/demo.intent",
        "start": { "line": 4, "column": 1, "offset": 64 },
        "end": { "line": 22, "column": 1, "offset": 420 }
      },
      "data": {
        "outputType": "PullRequest",
        "outputTypeSpan": "loc.4"
      }
    }
  ],
  "edges": [
    {
      "from": "goal:ship_checkout_fix",
      "to": "goal:ship_checkout_fix:completion",
      "kind": "completes"
    }
  ]
}
```

Required top-level fields are `schema_version`, `ast_schema_version`, `source`,
`package`, `ok`, `diagnostics`, `nodes`, and `edges`; `source` and `package`
must be strings. Node ids are stable and unique within one graph payload
because runtime edge resolution requires stable unique node ids. Graph
validation emits `INTENT_GRAPH_NODE_DUPLICATE` when two graph nodes share the
same id. Graph validation requires every edge endpoint to resolve to a node id
emitted in the same payload and requires emitted graphs to be acyclic over
dependency and execution edge kinds. Graph validation also emits
`INTENT_GRAPH_STEP_PLAN_INVALID` when a `Step` node lacks exactly one incoming
`plans` edge from its owning `Goal`, or when incoming `plans` edges are not from
that owning `Goal`. Graph validation emits
`INTENT_GRAPH_STEP_SEQUENCE_INVALID` when a goal with multiple `Step` nodes does
not have exactly one linear `precedes` chain across those steps, or when the
`Step` producing `Completion` is not the tail step of that chain. The graph
command may emit `ok: false` with diagnostics for inspection, but runtimes must
treat that graph as non-executable.

Next graph envelope validation milestone:

- A runtime must accept only its supported `schema_version` and
  `ast_schema_version` pair, starting with `intent.graph.v0` and
  `intent.ast.v0`.
- An unsupported or missing envelope version emits the stable diagnostic code
  `INTENT_GRAPH_ENVELOPE_UNSUPPORTED`.
- Executable graph payloads must include non-empty `source` and `package`
  provenance strings after trimming before runtime validation continues.
  Missing, non-string, or blank envelope provenance emits
  `INTENT_GRAPH_ENVELOPE_INVALID` before collection, node, or edge semantic
  validation because diagnostics, provenance, graph ids, and package-scoped
  runtime contracts need stable origins.
- Executable graph payloads must include `nodes` and `edges` arrays. Missing
  or non-array collections emit `INTENT_GRAPH_SHAPE_INVALID`.
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
  `from`, `to`, and `kind` values. Blank structural strings emit
  `INTENT_GRAPH_SHAPE_INVALID` before duplicate, endpoint, or edge-kind
  validation.
- Graph diagnostic payloads are part of the executable/diagnostic envelope
  contract. `diagnostics` must be an array, and every diagnostic record must be
  an object with `severity: "error"`, non-empty `code` and `message` strings,
  and a valid `span`. A malformed diagnostic record emits a stable graph
  validation diagnostic and makes the graph non-executable even when
  non-executable graph output is allowed for tooling inspection.
- Executable graph edge records may carry `data`; when present it must be an
  object. Any `sourceSpan` or `targetSpan` inside edge `data` must be a valid
  span before runtime dependency or provenance logic can use it.
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
- Runtime memory metadata is part of graph validation. `Memory` nodes must carry
  raw `data.retention` as an array and structured `data.retentionRules` as a
  non-empty array. Every structured retention rule must include non-empty `raw`,
  `subject.raw`, and `until.raw` strings, and `until.raw` must be one of
  `goal_complete`, `goal.completed`, or a bounded duration such as `30d`.
  Malformed memory lifecycle data emits `INTENT_GRAPH_MEMORY_INVALID` and makes
  the graph non-executable because runtimes must not infer retention policy.
- Runtime step policy metadata is part of graph validation. `Policy` nodes must
  carry `data.policyKind` as `timeout` or `retry`, non-empty `data.policy`, and
  non-empty `data.ownerStep`. Malformed step execution policy data emits
  `INTENT_GRAPH_POLICY_INVALID` and makes the graph non-executable because
  runtimes must not infer timeout or retry behavior.
- Runtime approval gate metadata is part of graph validation. `Approval` nodes
  must carry non-empty `data.approval` and non-empty `data.ownerStep`.
  Malformed step approval gate data emits `INTENT_GRAPH_APPROVAL_INVALID` and
  makes the graph non-executable because runtimes must not infer approval
  identity or step ownership.
- Runtime checkpoint metadata is part of graph validation. `Checkpoint` nodes
  must carry non-empty `data.checkpoint` and non-empty `data.ownerStep`.
  Malformed step checkpoint data emits `INTENT_GRAPH_CHECKPOINT_INVALID` and
  makes the graph non-executable because runtimes must not infer checkpoint
  identity or step ownership.
- A malformed graph envelope, including an envelope with unsupported versions
  or any graph validation diagnostic, is non-executable even when emitted for
  tooling/debug inspection.
- Executable graph payloads must have `ok: true` and `diagnostics: []`.
  `ok: false` or stale diagnostics mean the payload is a diagnostic artifact,
  not an executable contract.

## Contract Validation

Validation should cover both fixtures and output schemas:

```shell
node intent/bin/intent.mjs parse intent/fixtures/valid_code_change.intent
node intent/bin/intent.mjs check intent/fixtures/valid_code_change.intent
node intent/bin/intent.mjs graph intent/fixtures/valid_code_change.intent
node --test intent/test/*.test.mjs
```

Expected validation behavior:

- Valid fixtures parse, check with `ok: true`, and emit graph output with
  `ok: true`.
- Invalid fixtures fail `check` with exit code `1`, `ok: false`, stable
  diagnostic codes, and source spans.
- Parse, check, and graph stdout must validate against their matching schema
  files when schema validation is enabled.
- A graph payload is executable only when it validates against
  `intent.graph.v0.schema.json`, has `ok: true`, and has an empty
  `diagnostics` array.

## Checker Responsibilities

The checker consumes a complete AST and produces either a checked model or
blocking diagnostics.

- Bind package, imports, declarations, block-local names, step inputs, and goal
  state without implicit globals.
- Reject duplicate type names in the file, duplicate goal names in the file,
  duplicate goal input names in a goal, duplicate step names in a goal, and
  duplicate step input names in a step.
- Reject files with no goal declarations with `INTENT_GOAL_MISSING` at the
  source span.
- Reject unsupported parsed raw goal statements with
  `INTENT_UNSUPPORTED_SYNTAX` at the statement span.
- Duplicate goal and step parameter diagnostics should use the duplicate
  parameter span, not the enclosing goal or step span.
- Resolve every type reference against built-ins and file-local type
  declarations.
- Bind step inputs against goal inputs and earlier step outputs in source order.
- When a goal declares an output type and has plan steps, require the final
  plan step output type to exactly match the goal output type. If it differs,
  emit `INTENT_TYPE_MISMATCH` at the final step output type span.
- Assign first-prototype trust zones to source values. Repo contexts are
  trusted local sources and are not capability-enforced yet; structured
  `context documents(...)` sources are trusted local sources that require
  `file read path` capability coverage; structured `context web(...)` sources
  are untrusted external sources that require `web read domain` capability
  coverage; literals and checker-approved policy outputs are trusted.
- Type check expressions, inputs, outputs, context values, state values, step
  results, verification predicates, and effect arguments.
- Reject undeclared effects and effect calls not covered by an in-scope
  capability.
- Check simple capability constraints for file paths, shell commands, context
  source file paths, context source web domains, web/http read domains, and git
  commit messages, git push branches or remotes, secret read names, ticket
  update ids, and deploy targets.
- Preserve grant-level source spans when capability body grants are parsed, and
  use those spans in AST output, graph capability grants, allowed-grant
  diagnostics, and provenance metadata.
- Treat effects covered by a capability with `approval required` as requiring a
  step-local `approval ...` gate, and emit `INTENT_APPROVAL_MISSING` when the
  owning step has no approval gate.
- Normalize and compare constrained resources such as paths, commands, domains,
  branches, secret names, ticket ids, deploy targets, and approval targets.
- Require verification gates for every goal and ensure they are pure assertions
  except for supported verification effects.
- Bind verification shell requirements to declared shell run capability grants.
- Bind structured web and documents context sources to declared read capability
  grants, and emit `INTENT_CONTEXT_UNDECLARED` when no in-scope grant covers
  the requested source.
- Prefer argument-level spans for denied constrained resources: capability
  denials, unsafe shell trust-flow denials, structured context source denials,
  and verification shell denials should point at the parsed `path`, `command`,
  `url`, `domain`, `branch`, `remote`, `message`, `name`, `id`, `target`, or
  positional argument span that caused the denial.
- Emit `INTENT_VERIFY_IMPURE` for side-effect calls inside goal-level `verify`
  requirements, including file writes, git commits, git pushes, web or HTTP
  reads, deploys, and ticket updates.
- Parse step-body `require ...` lines as step requirements, separate from
  goal-level verification requirements.
- Parse step-body `approval ...` lines as step approval gates owned by their
  containing step.
- Emit `INTENT_APPROVAL_INVALID` at the approval line span when an approval
  gate label is empty after trimming.
- Parse step-body `checkpoint ...` lines as step checkpoints owned by their
  containing step.
- Emit `INTENT_CHECKPOINT_INVALID` at the checkpoint line span when a
  checkpoint label is empty after trimming.
- Parse step-body `timeout ...` and `retry ...` lines as step policy
  statements owned by their containing step, and emit `INTENT_POLICY_INVALID`
  when policy syntax is invalid.
- Enforce invariant placement, emit invariant statements as `Invariant` nodes,
  and attach those nodes to the graph as guards.
- Enforce `deny production_deploy` by rejecting `Deploy` effects targeting
  `production` with `INTENT_INVARIANT_VIOLATION` at the invariant line span.
- Enforce `deny secret_write` by rejecting file write effects whose path or name
  looks like a secret, for example `.env`, `secret`, `token`, `credential`,
  `key`, or `password`, with `INTENT_INVARIANT_VIOLATION` at the invariant line
  span.
- Enforce `deny unrelated_file_write` by rejecting file write effects whose path
  is outside declared `repo(...)` context roots, with
  `INTENT_INVARIANT_VIOLATION` at the invariant line span.
- Reject unsafe trust flows, including untrusted data flowing into executable
  commands, write targets, secrets, or approval decisions without policy.
- Emit `INTENT_TRUST_FLOW_UNSAFE` for nonliteral shell command arguments that
  are not already trusted by the checker.
- Require memory and checkpoint state to be scoped, serializable, and assigned a
  retention lifecycle.
- Emit `INTENT_MEMORY_UNSCOPED` when a memory block has no parsed
  `retain ... until ...` retention rule.
- Emit `INTENT_MEMORY_RETENTION_INVALID` when a parsed retention rule uses an
  unsupported lifecycle target.
- Build dependency edges from step inputs, produced values, checks, approvals,
  checkpoints, policies, and completion gates.
- Emit step requirements as `Check` nodes with `requires` edges into the owning
  step and `gates` edges to the owning goal.
- Emit step approval gates as `Approval` nodes, list them on the owning `Step`
  node data, and connect each one with an `approves` edge from that `Approval`
  node to the owning `Step`. Approval labels must be non-empty after trimming;
  empty labels such as `approval ""` are `INTENT_APPROVAL_INVALID` at the
  approval line span and make graph output non-executable.
- For approval-required effects, also connect a step `Approval` node to each
  matching `Effect` node with an `approves` edge and record the approval policy
  on the authorizing `Capability` node.
- Emit step checkpoints as `Checkpoint` nodes with non-empty `data.checkpoint`
  and `data.ownerStep`, list them on the owning `Step` node data, and connect
  each one with a `checkpoints` edge from that `Step`.
- Emit step timeout and retry policies as `Policy` nodes, list them on the
  owning `Step` node data, and connect each one with a `timeouts` or `retries`
  edge from that `Policy` node to the owning `Step`.
- Emit each invariant statement as an `Invariant` node with `guards` edges to
  completion and to every effect, checkpoint, and step requirement check in the
  same goal.
- Reject execution cycles unless a future bounded-loop form declares progress.

## Step Input Binding

Step inputs are bound by type in the first prototype. The checker walks each
plan in source order.

- The initial binding environment contains the goal inputs.
- A step input resolves when its normalized type exactly matches a goal input
  type or an earlier step output type.
- A step output becomes available only after that step's inputs have been
  checked.
- Step input names are local labels and do not create cross-step references.
- Bound input graph data keeps the source parameter span from the goal or step
  header that declared the parameter and the target parameter span from the step
  input that consumes it.
- There are no implicit conversions, field projections, destructuring, or
  forward references.
- If no prior value has the required type, the checker emits
  `INTENT_STEP_INPUT_UNRESOLVED`.

Every successful binding is also emitted as graph data dependency:

- Each goal input becomes an `input` graph node with `scope: "goal"`.
- Each step input becomes an `input` graph node with `scope: "step"` and the
  owning step id.
- A step input bound to a goal input creates a `data` edge from the goal input
  node to the step input node. Its edge `data` may include `sourceSpan` for the
  goal parameter and `targetSpan` for the step parameter.
- A step input bound to an earlier step output creates a `data` edge from the
  producing step node to the step input node. Its edge `data` may include
  `sourceSpan` for the producing output type and `targetSpan` for the step
  parameter.
- A step input node creates a `requires` edge to its owning step, so execution
  waits for the bound value before the step can run. Its edge `data` may include
  `targetSpan` for the required step parameter.
- The final executable step creates a `produces` edge to the goal completion
  node. Its edge `data` may include `sourceSpan` for the final step output type
  and `targetSpan` for the goal output type.
- Graph data-edge validation emits `INTENT_GRAPH_DATA_INVALID` when a `data`
  edge does not connect either a goal `Input` node or step producer to a step
  `Input` consumer.

## Effect Call Arguments

The parser extracts simple effect calls from expression text so the checker can
validate capability coverage before graph emission.

```json
{
  "callee": "shell.exec",
  "args": [
    {
      "name": "command",
      "kind": "string",
      "value": "npm test",
      "span": "loc.22"
    }
  ],
  "argKinds": ["string"],
  "argSpans": { "command": "loc.22" },
  "raw": "shell.exec(command: \"npm test\")",
  "span": "loc.21"
}
```

Rules:

- Positional and named arguments are retained in source order.
- `argKinds` retain each argument kind before checker normalization.
- `argSpans` maps `_0`, `_1`, and other positional keys or named argument keys
  to the exact argument token span. It is required for context calls, effect
  calls, and verification shell calls.
- Literal string, number, and boolean values are normalized for checking while
  retaining raw token spans.
- Nested calls may be parsed as argument values, but the first capability
  milestone only checks literal file path, shell command, structured context web
  URL or domain, structured context documents path, web/http read URL or domain,
  git commit messages, git push branch or remote arguments, secret read names,
  ticket update ids, and deploy targets.
- Unknown identifiers in effect arguments are allowed to remain unresolved only
  when the effect call is not used for a capability-constrained resource or a
  trust-sensitive resource.

## Capability Grants

Capability bodies preserve every body line as raw text. Body lines that match a
supported grant shape are also parsed into structured `CapabilityGrant` entries:

```intent
capability files {
  read path: "./src/**"
  file.read(path: "intent/STATIC_MODEL.md")
}
```

```json
{
  "kind": "CapabilityGrant",
  "actionPath": "read",
  "constraints": [{ "key": "path", "value": "./src/**", "span": "loc.8" }],
  "raw": "read path: \"./src/**\"",
  "span": "loc.8"
}
```

Rules:

- `span` is required on every structured grant object.
- The grant span covers the exact grant line, including the action path and
  constraint text, and excludes trailing unrelated whitespace.
- Constraint values keep their own token spans for argument-level diagnostics.
- Parsed dotted grant calls retain the dotted action path and ordered arguments
  from the source call.
- Graph `Capability` node `data.grants` entries carry the same grant-level
  `span` as the AST `CapabilityGrant`.
- Diagnostics and provenance that mention allowed grants must use the
  grant-level span when a structured grant is available.

## Context Sources

Context declarations preserve their source call as structured data:

```intent
context repo(path: "./")
context documents(path: "intent/STATIC_MODEL.md")
context web(url: "https://docs.example.com/guide")
```

The parsed `ContextDecl` retains the source name, ordered args, argKinds,
argSpans, original expression text, source span, and checker-owned trust
metadata:

```json
{
  "kind": "ContextDecl",
  "source": "repo",
  "args": [{ "name": "path", "value": "./", "span": "loc.6" }],
  "argKinds": ["string"],
  "argSpans": { "path": "loc.6" },
  "expression": "repo(path: \"./\")",
  "trust": { "zone": "trusted", "source": "local" }
}
```

Rules:

- `source` is the callee path from the context call.
- `args` retain positional and named argument values in source order.
- `argKinds` retain each argument kind before checker normalization.
- `argSpans` maps positional keys such as `_0` and named keys such as `path`,
  `url`, or `domain` to the source span of that argument.
- `expression` is the original context call text.
- Repo contexts are trusted local source values in the first checker prototype
  and are not capability-enforced yet.
- Structured `context documents(...)` declarations are trusted local source
  values. They use the first positional argument or a named `path` argument and
  must be covered by an in-scope `file read path: "..."` capability grant.
- Structured `context web(...)` declarations are untrusted external source
  values. They use the first positional argument or a named `url` or `domain`
  argument and must be covered by an in-scope `web read domain: "..."`
  capability grant.
- If no matching capability covers a structured `web(...)` or
  `documents(...)` context source, the checker emits
  `INTENT_CONTEXT_UNDECLARED`.
- A successful context source binding creates an `authorizes` edge from the
  matching `Capability` node to the `Context` node.
- Browser/page state is untrusted external source data in the first checker
  prototype.
- Graph `Context` nodes carry the same source name, args, argKinds, argSpans,
  expression, and trust zone/source data as their originating `ContextDecl`.

## Step Requirements

Step bodies may contain `require ...` lines that declare preconditions or
required checks for only that step:

```intent
plan {
  step run_tests(patch: GitDiff) -> TestReport {
    require patch.applies
    require shell("npm test").exit_code == 0
  }
}
```

Rules:

- Step-body requirements are parsed into the owning `StepDecl` as step
  requirements, not into the goal `VerifyBlock`.
- Each step requirement emits one graph `Check` node whose span is the
  `require ...` line.
- The graph builder creates a `requires` edge from the step requirement `Check`
  node into the owning `Step`, so the step cannot run until the check succeeds.
- The graph builder creates a `gates` edge from the step requirement `Check`
  node to the owning `Goal`, so the requirement is scoped to that goal.
- Step requirement checks do not create `verifies` edges to the goal
  `Completion` node. Goal-level `verify` requirements remain the only checks
  that verify completion.

## Step Approvals

Step bodies may contain `approval ...` lines that declare manual approval gates
for only that step:

```intent
plan {
  step deploy_patch(report: TestReport) -> Release {
    approval release_manager
    approval change_advisory_board
  }
}
```

Rules:

- Step-body approvals are parsed into the owning `StepDecl` as step approval
  gates.
- Each step approval gate emits one graph `Approval` node whose span is the
  `approval ...` line.
- The owning `Step` node data lists approval summaries in source order.
- The graph builder creates an `approves` edge from each approval `Approval`
  node to the owning `Step`, so the step cannot run until approval is granted.
- Runtime graph validation requires every `Approval` node to carry non-empty
  `data.approval` and non-empty `data.ownerStep`; malformed approval gate data
  emits `INTENT_GRAPH_APPROVAL_INVALID` and makes the graph non-executable.
- Step approval gates do not create `verifies` edges to the goal `Completion`
  node and do not replace capability policy approval requirements.
- Approval gate labels must be non-empty after trimming.
- An empty approval label, including `approval ""`, emits
  `INTENT_APPROVAL_INVALID` at the approval line span and makes graph output
  non-executable.
- When a capability authorizing an effect contains `approval required`, the
  effect's owning step must contain at least one step-local `approval ...` gate.
  The graph builder also creates an `approves` edge from a step `Approval` node
  to each approval-required `Effect` node in that step. If the owning step has
  no approval gate, the checker emits `INTENT_APPROVAL_MISSING`.

## Step Checkpoints

Step bodies may contain `checkpoint ...` lines that declare recoverable state
or progress markers for only that step:

```intent
plan {
  step run_tests(patch: GitDiff) -> TestReport {
    checkpoint patch_applied
    checkpoint test_report_written
  }
}
```

Rules:

- Step-body checkpoints are parsed into the owning `StepDecl` as step
  checkpoint statements.
- Each step checkpoint emits one graph `Checkpoint` node whose span is the
  `checkpoint ...` line.
- The owning `Step` node data lists checkpoint summaries in source order.
- The graph builder creates a `checkpoints` edge from the owning `Step` to each
  checkpoint `Checkpoint` node.
- Checkpoint labels must be non-empty after trimming.
- Runtime graph validation also requires each `Checkpoint` node to carry
  non-empty `data.checkpoint` and non-empty `data.ownerStep`. Malformed
  checkpoint node data emits `INTENT_GRAPH_CHECKPOINT_INVALID` and makes graph
  output non-executable.
- An empty checkpoint label, including `checkpoint ""`, emits
  `INTENT_CHECKPOINT_INVALID` at the checkpoint line span and makes graph
  output non-executable.
- Step checkpoints do not create `verifies` edges to the goal `Completion`
  node and do not replace memory retention rules.

## Step Policies

Step bodies may contain `timeout ...` and `retry ...` lines that declare
execution policy for only that step:

```intent
plan {
  step run_tests(patch: GitDiff) -> TestReport {
    timeout 2m
    retry max 3
  }
}
```

Rules:

- Step-body timeout and retry lines are parsed into the owning `StepDecl` as
  step policy statements.
- `timeout` preserves the raw duration text; `retry` preserves the raw policy
  text.
- Timeout values must be simple positive durations with a positive integer and
  unit `s`, `m`, `h`, or `d`, such as `10s`, `5m`, `2h`, or `1d`.
- Retry policies must be `max N`, where `N` is a positive integer.
- Invalid timeout or retry policy syntax emits `INTENT_POLICY_INVALID` at the
  policy line span.
- Each step policy emits one graph `Policy` node whose span is the policy line.
- Each graph `Policy` node records `data.policyKind` as `timeout` or `retry`,
  `data.policy` as the non-empty raw policy text, and `data.ownerStep` as the
  non-empty owning step id.
- The owning `Step` node data lists timeout and retry summaries in source
  order.
- The graph builder creates a `timeouts` edge from each timeout `Policy` node
  to the owning `Step`.
- The graph builder creates a `retries` edge from each retry `Policy` node to
  the owning `Step`.
- Step policies do not create `verifies` edges to the goal `Completion` node
  and do not replace approval, checkpoint, or capability policy requirements.

## Invariant Guards

Invariant blocks contain always-on `deny ...` statements. Each statement emits
one graph `Invariant` node whose span is the `deny ...` line.

Rules:

- The graph builder creates a `guards` edge from each `Invariant` node to the
  goal `Completion` node.
- The graph builder also creates `guards` edges from each `Invariant` node to
  every `Effect`, `Checkpoint`, and step-scoped requirement `Check` node in the
  same goal.
- Graph validation emits `INTENT_GRAPH_GUARD_INVALID` when an `Invariant` node
  is missing its `guards` edge to `Completion` or to any `Effect`,
  `Checkpoint`, or step-scoped `Check` node in the same goal.
- Enforce `deny production_deploy` by rejecting any `Deploy` effect whose
  normalized `target` is `production` with `INTENT_INVARIANT_VIOLATION` at the
  invariant line span.
- Enforce `deny secret_write` by rejecting file write effects whose path or name
  looks like a secret, for example `.env`, `secret`, `token`, `credential`,
  `key`, or `password`, with `INTENT_INVARIANT_VIOLATION` at the invariant line
  span.
- Enforce `deny unrelated_file_write` by rejecting file write effects whose path
  is outside declared `repo(...)` context roots, with
  `INTENT_INVARIANT_VIOLATION` at the invariant line span.
- Invariant guards do not replace capability, checkpoint, step requirement, or
  verification edges. They make always-on rules visible wherever side effects,
  recovery boundaries, and step-local checks can affect execution.

## Memory Retention

Memory blocks declare retained state or evidence and must make the lifecycle
explicit. Each `memory` block must contain at least one parsed retention line:

```intent
memory session audit_evidence {
  retain test_report until goal.completed
}
```

The parser preserves every memory body line as raw text in `retention`. Lines
matching `retain ... until ...` are also parsed into structured
`retentionRules` entries:

```json
{
  "kind": "MemoryRetention",
  "subject": { "raw": "test_report", "span": "loc.12" },
  "until": { "raw": "goal.completed", "span": "loc.13" },
  "raw": "retain test_report until goal.completed",
  "span": "loc.11"
}
```

Rules:

- A memory block with no parsed retention entries emits
  `INTENT_MEMORY_UNSCOPED`.
- Supported runtime lifecycle targets are `goal_complete`, `goal.completed`,
  or bounded durations written as positive integers with `s`, `m`, `h`, or `d`
  units, such as `30d`.
- A malformed `retain` line or unsupported lifecycle target emits
  `INTENT_MEMORY_RETENTION_INVALID`.
- Retention entries are checker-owned lifecycle data, not opaque comments.
- The graph builder emits `retentionRules` in the owning `Memory` node data so
  runtimes can enforce retention without reparsing memory body text.
- Runtime graph validation also requires each `Memory` node to carry
  `data.retention` as an array and `data.retentionRules` as a non-empty array.
  Every structured retention rule must include non-empty `raw`, `subject.raw`,
  and `until.raw` strings. Invalid graph memory lifecycle data emits
  `INTENT_GRAPH_MEMORY_INVALID` and makes graph output non-executable.

## Trust Flow

The first trust-flow checker is intentionally narrow. It tracks only the trust
state needed to prevent untrusted web-derived values from becoming executable
shell commands.

Trust zones:

- `trusted`: string literals, numeric literals, boolean literals, and values
  produced by checker-approved policies or trusted effects.
- `untrusted`: web contexts, browser/page state, remote HTML, remote JSON, URLs,
  query strings, form fields, and any values derived from them.
- `unknown`: values whose source is not modeled by the first prototype.

Rules:

- Web context declarations produce untrusted values by default.
- Documents context declarations produce trusted local values after matching
  `file read path` capability coverage.
- Repo context declarations produce trusted local values and are not
  capability-enforced yet.
- Trust propagates through step input binding and graph `data` edges.
- A value derived from any untrusted input remains untrusted unless a future
  policy or verifier explicitly upgrades it.
- Shell command arguments are executable trust sinks.
- A shell command argument is accepted when it is a string literal or when the
  checker can prove the argument value is trusted.
- A nonliteral shell command argument that is not trusted emits
  `INTENT_TRUST_FLOW_UNSAFE` at the argument span and makes graph output
  non-executable with `ok: false`.

## Capability Constraints

The first constraint checker supports only direct string-literal matches for
file paths, shell commands, web/http read domains, git commit messages, git push
branches or remotes, secret read names, ticket update ids, and deploy targets. A
capability authorizes an effect call when the effect family matches and every
constrained argument is covered by the capability.

Context source constraints:

- Structured `context documents(...)` sources use the first positional argument
  or a named `path` argument.
- A documents context source is valid only when an in-scope capability grants
  `file read path: "..."`.
- Structured `context web(...)` sources use the first positional argument or a
  named `url` or `domain` argument.
- A web context source is valid only when an in-scope capability grants
  `web read domain: "..."`.
- Documents context paths use the same normalization and matching rules as file
  path constraints.
- Web context URL and domain arguments use the same normalization and matching
  rules as web/http read constraints.
- If no matching grant covers the normalized path, URL host, or domain
  argument, the checker emits `INTENT_CONTEXT_UNDECLARED` at that parsed
  argument span. If the source call has no parsed argument span, the diagnostic
  uses the wider context source call span.
- A successful context source binding creates an `authorizes` edge from the
  matching `Capability` node to the `Context` node.

File path constraints:

- File effects use the first positional argument or a named `path` argument.
- Paths are normalized relative to the source package root without following
  symlinks.
- `.` and `..` segments are collapsed; paths that escape the package root are
  denied.
- A capability path ending in `/**` authorizes files below that directory.
- A capability path containing `*` supports a single path-segment wildcard.
- A capability path without a wildcard authorizes only that exact path.

Shell command constraints:

- Shell effects use the first positional argument or a named `command` argument.
- Commands are compared after trimming leading and trailing ASCII whitespace and
  collapsing internal ASCII whitespace runs to a single space.
- The first milestone allows exact command strings only; globs, regex, shell
  parsing, environment mutation, and command prefixes are unsupported.
- Nonliteral shell command arguments must resolve to trusted values. Untrusted
  or unknown nonliteral command arguments emit `INTENT_TRUST_FLOW_UNSAFE`.

Web/http read constraints:

- Web/http read effects use the first positional argument or a named `url` or
  `domain` argument.
- URL arguments must be absolute `http` or `https` URLs. The checker extracts
  and normalizes the URL host by lowercasing it, removing a trailing dot, and
  ignoring ports, paths, query strings, and fragments for capability matching.
- Domain arguments are normalized the same way as URL hosts, except they are
  already host names rather than full URLs.
- A web/http read effect is valid only when an in-scope capability grants
  `read domain: "..."`.
- An exact domain grant authorizes only the same normalized host.
- A wildcard domain grant starts with `*.` and authorizes descendant hosts that
  end with the granted suffix. For example, `*.example.com` authorizes
  `docs.example.com` and `api.docs.example.com`, but not `example.com`.
- If no exact or wildcard domain grant covers the normalized URL host or domain
  argument, the checker emits `INTENT_CAPABILITY_DENIED`.

Git commit constraints:

- Git commit effects use a named `message` argument as the constrained
  resource.
- `GitCommit(message: "...")` and `git.commit(message: "...")` are valid only
  when an in-scope capability grants `git commit message: "..."`, written in
  source as `capability git { commit message: "..." }`.
- Commit messages are normalized by trimming leading and trailing ASCII
  whitespace before comparison. Matching is exact after normalization;
  wildcards, templates, environment expansion, and generated messages are
  unsupported.
- If no git commit grant covers the normalized message, the checker emits
  `INTENT_CAPABILITY_DENIED`.
- A successful git commit binding creates an `authorizes` edge from the
  matching `Capability` node to the `GitCommit` `Effect` node.

Secret read constraints:

- Secret read coverage is a Phase 2 static-model check only; it authorizes the
  request shape and does not read, validate, serialize, or propagate secret
  values.
- Secret read effects use a named `name` argument as the constrained resource.
- `SecretRead(name: "...")` is valid only when an in-scope capability grants
  `secret read name: "..."`, written in source as
  `capability secret { read name: "..." }`.
- Secret names are normalized by trimming leading and trailing ASCII whitespace
  before comparison. Matching is exact after normalization; wildcards, aliases,
  environment expansion, and value inspection are unsupported.
- If no secret grant covers the normalized name, the checker emits
  `INTENT_CAPABILITY_DENIED`.

Ticket update constraints:

- Ticket update effects use a named `id` argument as the constrained resource.
- `TicketUpdate(id: "...")` is valid only when an in-scope capability grants
  `ticket update id: "..."`, written in source as
  `capability ticket { update id: "..." }`.
- Ticket ids are normalized by trimming leading and trailing ASCII whitespace
  before comparison. Matching is exact after normalization; wildcards, aliases,
  project prefixes, and lookup expansion are unsupported.
- If no ticket grant covers the normalized id, the checker emits
  `INTENT_CAPABILITY_DENIED`.
- A successful ticket update binding creates an `authorizes` edge from the
  matching `Capability` node to the `TicketUpdate` `Effect` node.

Deploy constraints:

- Deploy effects use a named `target` argument as the constrained resource.
- `Deploy(target: "...")` is valid only when an in-scope capability grants
  `deploy deploy target: "..."`, written in source as
  `capability deploy { deploy target: "..." }`.
- Deploy targets are normalized by trimming leading and trailing ASCII
  whitespace before comparison. Matching is exact after normalization;
  wildcards, aliases, environment expansion, and target lookup are unsupported.
- If no deploy grant covers the normalized target, the checker emits
  `INTENT_CAPABILITY_DENIED`.
- A successful deploy binding creates an `authorizes` edge from the matching
  `Capability` node to the `Deploy` `Effect` node.

Git push constraints:

- Git push effects use a named `branch` or `remote` argument as the constrained
  resource.
- `git.push(branch: "...")` is valid only when an in-scope capability grants
  `push branch: "..."`.
- `git.push(remote: "...")` is valid only when an in-scope capability grants
  `push remote: "..."`.
- Branch arguments are simple branch names. They are normalized by trimming
  leading and trailing ASCII whitespace and removing one leading `refs/heads/`
  prefix before comparison.
- Remote arguments are simple remote names. They are normalized by trimming
  leading and trailing ASCII whitespace before comparison.
- Git branch and remote matching is exact after normalization; wildcards,
  refspecs, URLs, and shell-expanded arguments are unsupported.
- If no branch or remote grant covers the normalized argument, the checker emits
  `INTENT_CAPABILITY_DENIED`.

When no in-scope capability covers a constrained resource, the checker emits
`INTENT_CAPABILITY_DENIED` with the denied argument, denied value, and allowed
grants. The diagnostic span is the constrained argument's parsed `argSpans`
entry when available, and otherwise falls back to the effect call span.

Capability approval requirements:

- A capability body may contain `approval required`.
- A capability with `approval required` still authorizes only matching effects;
  the approval policy applies after the normal capability constraint match.
- Any effect authorized by that capability is approval-required in its owning
  step.
- The owning step must declare at least one step-local `approval ...` gate.
- If no step-local approval gate is present, the checker emits
  `INTENT_APPROVAL_MISSING` at the effect call span.
- Approval gate labels must be non-empty after trimming. An empty label such as
  `approval ""` emits `INTENT_APPROVAL_INVALID` at the approval line span and
  makes graph output non-executable.
- Graph output records the approval policy on the authorizing `Capability` node
  and creates `approves` edges from step `Approval` nodes to matching
  approval-required `Effect` nodes.

## Verification Shell Binding

Verification requirements may call shell checks as completion gates:

```intent
verify {
  require shell("npm test").exit_code == 0
  require shell(command: "npm run lint").exit_code == 0
}
```

Rules:

- `shell("command")` and `shell(command: "command")` in a `verify` requirement
  are verification shell requests, not plan step effects.
- Verification shell requests use the same command argument normalization as
  shell command constraints.
- Verification shell requests preserve `args`, `argKinds`, and `argSpans` on
  the graph `Check` node effect data.
- A verification shell request is valid only when an in-scope capability grants
  shell `run` for the normalized command.
- A successful binding creates an `authorizes` edge from the matching
  `Capability` node to the `Check` node.
- If no declared shell run grant covers the command, the checker emits
  `INTENT_VERIFY_UNDECLARED` with the denied command and allowed shell run
  grants. The diagnostic span is the shell command argument span when parsed,
  and otherwise falls back to the verification shell call span.

## Verification Purity

Goal-level `verify` requirements are completion assertions, not execution
steps. They may use predicate logic and supported verification effects only.
The supported verification effect for this milestone is a shell check written
as `shell("...")` or `shell(command: "...")`; it remains subject to
verification shell binding and capability checks.

Any side-effecting operation inside a goal-level `verify` requirement is
impure. Calls such as `FileWrite`, `GitCommit`, `GitPush`, `web.read`,
`http.get`, deploy operations, or ticket updates emit `INTENT_VERIFY_IMPURE` at
the impure call span and make graph output non-executable.

## Diagnostics

Diagnostics are structured and stable enough for editor and CI use.

```json
{
  "code": "INTENT_EFFECT_UNDECLARED",
  "severity": "error",
  "message": "Effect ShellExec is not declared for step run_tests.",
  "span": {
    "file": "intent/examples/demo.intent",
    "start": { "line": 31, "column": 5, "offset": 711 },
    "end": { "line": 31, "column": 28, "offset": 734 }
  },
  "related": [
    {
      "message": "Step declared FileRead only.",
      "span": {
        "file": "intent/examples/demo.intent",
        "start": { "line": 27, "column": 13, "offset": 620 },
        "end": { "line": 27, "column": 21, "offset": 628 }
      }
    }
  ]
}
```

Initial diagnostic families:

- `INTENT_PARSE_ERROR`
- `INTENT_GOAL_MISSING`
- `INTENT_UNSUPPORTED_SYNTAX`
- `INTENT_NAME_UNRESOLVED`
- `INTENT_NAME_DUPLICATE`
- `INTENT_TYPE_UNRESOLVED`
- `INTENT_TYPE_MISMATCH`
- `INTENT_STEP_INPUT_UNRESOLVED`
- `INTENT_EFFECT_UNDECLARED`
- `INTENT_CAPABILITY_DENIED`
- `INTENT_APPROVAL_MISSING`
- `INTENT_APPROVAL_INVALID`
- `INTENT_VERIFY_MISSING`
- `INTENT_VERIFY_IMPURE`
- `INTENT_VERIFY_UNDECLARED`
- `INTENT_INVARIANT_VIOLATION`
- `INTENT_TRUST_FLOW_UNSAFE`
- `INTENT_MEMORY_UNSCOPED`
- `INTENT_MEMORY_RETENTION_INVALID`
- `INTENT_CHECKPOINT_INVALID`
- `INTENT_POLICY_INVALID`
- `INTENT_GRAPH_ENVELOPE_UNSUPPORTED`
- `INTENT_GRAPH_SHAPE_INVALID`
- `INTENT_GRAPH_DIAGNOSTIC_INVALID`
- `INTENT_GRAPH_TRUST_INVALID`
- `INTENT_GRAPH_CAPABILITY_INVALID`
- `INTENT_GRAPH_APPROVAL_INVALID`
- `INTENT_GRAPH_CHECKPOINT_INVALID`
- `INTENT_GRAPH_MEMORY_INVALID`
- `INTENT_GRAPH_POLICY_INVALID`
- `INTENT_GRAPH_NODE_DUPLICATE`
- `INTENT_GRAPH_NODE_KIND_INVALID`
- `INTENT_GRAPH_EDGE_KIND_INVALID`
- `INTENT_GRAPH_EDGE_UNRESOLVED`
- `INTENT_GRAPH_DATA_INVALID`
- `INTENT_GRAPH_INPUT_UNBOUND`
- `INTENT_GRAPH_GOAL_COMPLETION_INVALID`
- `INTENT_GRAPH_COMPLETION_INVALID`
- `INTENT_GRAPH_GUARD_INVALID`
- `INTENT_GRAPH_AUTHORIZATION_INVALID`
- `INTENT_GRAPH_EFFECT_REQUEST_INVALID`
- `INTENT_GRAPH_STEP_SEQUENCE_INVALID`
- `INTENT_GRAPH_STEP_ATTACHMENT_INVALID`
- `INTENT_GRAPH_STEP_PLAN_INVALID`
- `INTENT_GRAPH_CYCLE`

Errors make graph output non-executable by setting `ok: false`. Warnings and
notes may be emitted with a checked graph when runtime behavior remains
unambiguous.

## Execution Graph Shape

The first prototype emits JSON with deterministic ordering by source order, then
node id. It is an intermediate contract for a local runtime.

```json
{
  "schema_version": "intent.graph.v0",
  "ast_schema_version": "intent.ast.v0",
  "source": "intent/examples/demo.intent",
  "package": "examples.demo",
  "ok": true,
  "diagnostics": [],
  "nodes": [
    {
      "id": "goal:ship_checkout_fix",
      "kind": "Goal",
      "label": "ship_checkout_fix",
      "span": "loc.4",
      "data": {
        "title": null,
        "parameters": [{ "name": "ticket", "type": "TicketRef", "span": "loc.4" }],
        "outputType": "PullRequest",
        "outputTypeSpan": "loc.4"
      }
    },
    {
      "id": "goal:ship_checkout_fix:input:ticket",
      "kind": "Input",
      "label": "ticket",
      "span": "loc.4",
      "data": {
        "scope": "goal",
        "type": "TicketRef",
        "trust": { "zone": "unknown", "source": "goal_input" }
      }
    },
    {
      "id": "goal:ship_checkout_fix:context:0",
      "kind": "Context",
      "label": "repo",
      "span": "loc.6",
      "data": {
        "source": "repo",
        "args": [{ "name": "path", "value": "./", "span": "loc.6" }],
        "argKinds": ["string"],
        "argSpans": { "path": "loc.6" },
        "expression": "repo(path: \"./\")",
        "trust": { "zone": "trusted", "source": "local" }
      }
    },
    {
      "id": "goal:ship_checkout_fix:capability:0",
      "kind": "Capability",
      "label": "tests",
      "span": "loc.7",
      "data": {
        "family": "shell",
        "action": null,
        "grants": [{ "action": "run", "key": "command", "value": "npm test" }],
        "approvalPolicy": "required"
      }
    },
    {
      "id": "goal:ship_checkout_fix:memory:audit_evidence",
      "kind": "Memory",
      "label": "audit_evidence",
      "span": "loc.10",
      "data": {
        "retention": ["retain test_report until goal.completed"],
        "retentionRules": [
          {
            "subject": { "raw": "test_report", "span": "loc.11" },
            "until": { "raw": "goal.completed", "span": "loc.11" },
            "raw": "retain test_report until goal.completed",
            "span": "loc.11"
          }
        ]
      }
    },
    {
      "id": "goal:ship_checkout_fix:step:prepare_patch",
      "kind": "Step",
      "label": "prepare_patch",
      "span": "loc.12",
      "data": {
        "inputs": [{ "name": "ticket", "type": "TicketRef", "span": "loc.12" }],
        "outputType": "GitDiff",
        "outputTypeSpan": "loc.12",
        "effects": ["FileRead"]
      }
    },
    {
      "id": "goal:ship_checkout_fix:step:prepare_patch:input:ticket",
      "kind": "Input",
      "label": "ticket",
      "span": "loc.12",
      "data": {
        "scope": "step",
        "type": "TicketRef"
      }
    },
    {
      "id": "goal:ship_checkout_fix:step:run_tests",
      "kind": "Step",
      "label": "run_tests",
      "span": "loc.15",
      "data": {
        "inputs": [{ "name": "patch", "type": "GitDiff", "span": "loc.15" }],
        "outputType": "ShellExecResult",
        "outputTypeSpan": "loc.15",
        "effects": ["ShellExec"],
        "approvals": ["release_manager_review"],
        "requirements": [],
        "checkpoints": ["test_report_written"],
        "timeouts": ["2m"],
        "retries": ["max 3"]
      }
    },
    {
      "id": "goal:ship_checkout_fix:step:run_tests:approval:0",
      "kind": "Approval",
      "label": "release_manager_review",
      "span": "loc.16",
      "data": {
        "scope": "step",
        "ownerStep": "run_tests",
        "approval": "release_manager_review"
      }
    },
    {
      "id": "goal:ship_checkout_fix:step:run_tests:checkpoint:0",
      "kind": "Checkpoint",
      "label": "test_report_written",
      "span": "loc.16",
      "data": {
        "scope": "step",
        "ownerStep": "run_tests",
        "checkpoint": "test_report_written"
      }
    },
    {
      "id": "goal:ship_checkout_fix:step:run_tests:timeout:0",
      "kind": "Policy",
      "label": "2m",
      "span": "loc.16",
      "data": {
        "scope": "step",
        "ownerStep": "run_tests",
        "policyKind": "timeout",
        "policy": "2m"
      }
    },
    {
      "id": "goal:ship_checkout_fix:step:run_tests:retry:0",
      "kind": "Policy",
      "label": "max 3",
      "span": "loc.16",
      "data": {
        "scope": "step",
        "ownerStep": "run_tests",
        "policyKind": "retry",
        "policy": "max 3"
      }
    },
    {
      "id": "goal:ship_checkout_fix:step:run_tests:effect:0",
      "kind": "Effect",
      "label": "ShellExec",
      "span": "loc.16",
      "data": {
        "family": "shell",
        "action": "run",
        "args": { "command": "npm test" },
        "argKinds": { "command": "string" },
        "argSpans": { "command": "loc.16" },
        "expression": "ShellExec(command: \"npm test\")",
        "trust": {
          "sinks": [
            {
              "argument": "command",
              "zone": "trusted",
              "reason": "literal"
            }
          ]
        }
      }
    },
    {
      "id": "goal:ship_checkout_fix:step:run_tests:input:patch",
      "kind": "Input",
      "label": "patch",
      "span": "loc.15",
      "data": {
        "scope": "step",
        "type": "GitDiff",
        "trust": { "zone": "unknown", "source": "data_edge" }
      }
    },
    {
      "id": "goal:ship_checkout_fix:step:run_tests:requirement:0",
      "kind": "Check",
      "label": "shell(\"npm test\").exit_code == 0",
      "span": "loc.17",
      "data": {
        "scope": "step",
        "ownerStep": "run_tests",
        "assertion": "Require",
        "requirement": "shell(\"npm test\").exit_code == 0"
      }
    },
    {
      "id": "goal:ship_checkout_fix:invariant:0",
      "kind": "Invariant",
      "label": "secrets.never_written",
      "span": "loc.18",
      "data": {
        "assertion": "Deny",
        "invariant": "secrets.never_written"
      }
    },
    {
      "id": "goal:ship_checkout_fix:verify:0",
      "kind": "Check",
      "label": "shell(\"npm test\").exit_code == 0",
      "span": "loc.19",
      "data": {
        "effect": {
          "family": "shell",
          "action": "run",
          "args": { "command": "npm test" },
          "argKinds": { "_0": "string" },
          "argSpans": { "_0": "loc.19" },
          "expression": "shell(\"npm test\")"
        }
      }
    },
    {
      "id": "goal:ship_checkout_fix:completion",
      "kind": "Completion",
      "label": "ship_checkout_fix",
      "span": "loc.4",
      "data": {
        "outputType": "PullRequest",
        "outputTypeSpan": "loc.4"
      }
    }
  ],
  "edges": [
    {
      "from": "goal:ship_checkout_fix:input:ticket",
      "to": "goal:ship_checkout_fix:step:prepare_patch:input:ticket",
      "kind": "data",
      "data": {
        "parameter": "ticket",
        "type": "TicketRef",
        "span": "loc.12",
        "trust": { "zone": "unknown" }
      }
    },
    {
      "from": "goal:ship_checkout_fix:step:prepare_patch:input:ticket",
      "to": "goal:ship_checkout_fix:step:prepare_patch",
      "kind": "requires",
      "data": { "parameter": "ticket", "type": "TicketRef", "span": "loc.12" }
    },
    {
      "from": "goal:ship_checkout_fix:step:prepare_patch",
      "to": "goal:ship_checkout_fix:step:run_tests:input:patch",
      "kind": "data",
      "data": {
        "parameter": "patch",
        "type": "GitDiff",
        "span": "loc.15",
        "trust": { "zone": "unknown" }
      }
    },
    {
      "from": "goal:ship_checkout_fix:step:run_tests:input:patch",
      "to": "goal:ship_checkout_fix:step:run_tests",
      "kind": "requires",
      "data": { "parameter": "patch", "type": "GitDiff", "span": "loc.15" }
    },
    {
      "from": "goal:ship_checkout_fix:capability:0",
      "to": "goal:ship_checkout_fix:step:run_tests:effect:0",
      "kind": "authorizes"
    },
    {
      "from": "goal:ship_checkout_fix:step:run_tests:approval:0",
      "to": "goal:ship_checkout_fix:step:run_tests",
      "kind": "approves"
    },
    {
      "from": "goal:ship_checkout_fix:step:run_tests:approval:0",
      "to": "goal:ship_checkout_fix:step:run_tests:effect:0",
      "kind": "approves"
    },
    {
      "from": "goal:ship_checkout_fix:step:run_tests",
      "to": "goal:ship_checkout_fix:step:run_tests:checkpoint:0",
      "kind": "checkpoints"
    },
    {
      "from": "goal:ship_checkout_fix:step:run_tests:timeout:0",
      "to": "goal:ship_checkout_fix:step:run_tests",
      "kind": "timeouts"
    },
    {
      "from": "goal:ship_checkout_fix:step:run_tests:retry:0",
      "to": "goal:ship_checkout_fix:step:run_tests",
      "kind": "retries"
    },
    {
      "from": "goal:ship_checkout_fix:step:run_tests:requirement:0",
      "to": "goal:ship_checkout_fix",
      "kind": "gates"
    },
    {
      "from": "goal:ship_checkout_fix:step:run_tests:requirement:0",
      "to": "goal:ship_checkout_fix:step:run_tests",
      "kind": "requires"
    },
    {
      "from": "goal:ship_checkout_fix:invariant:0",
      "to": "goal:ship_checkout_fix:step:run_tests:effect:0",
      "kind": "guards"
    },
    {
      "from": "goal:ship_checkout_fix:invariant:0",
      "to": "goal:ship_checkout_fix:step:run_tests:checkpoint:0",
      "kind": "guards"
    },
    {
      "from": "goal:ship_checkout_fix:invariant:0",
      "to": "goal:ship_checkout_fix:step:run_tests:requirement:0",
      "kind": "guards"
    },
    {
      "from": "goal:ship_checkout_fix:verify:0",
      "to": "goal:ship_checkout_fix",
      "kind": "gates"
    },
    {
      "from": "goal:ship_checkout_fix:verify:0",
      "to": "goal:ship_checkout_fix:completion",
      "kind": "verifies"
    },
    {
      "from": "goal:ship_checkout_fix:step:run_tests",
      "to": "goal:ship_checkout_fix:completion",
      "kind": "produces",
      "data": { "type": "ShellExecResult" }
    },
    {
      "from": "goal:ship_checkout_fix:invariant:0",
      "to": "goal:ship_checkout_fix:completion",
      "kind": "guards"
    },
    {
      "from": "goal:ship_checkout_fix",
      "to": "goal:ship_checkout_fix:completion",
      "kind": "completes"
    }
  ]
}
```

Required node kinds are `Goal`, `Input`, `Context`, `Capability`, `Memory`,
`Step`, `Effect`, `Check`, `Invariant`, `Approval`, `Checkpoint`, `Policy`, and
`Completion`.
Graph validation emits `INTENT_GRAPH_NODE_KIND_INVALID` when a graph node kind
is not one of those runtime-supported Intent graph node kinds.

Required edge kinds are `data`, `requires`, `produces`, `authorizes`,
`verifies`, `guards`, `gates`, `approves`, `checkpoints`, `timeouts`,
`retries`, `completes`, `plans`, `precedes`, `requests`, `supplies`,
`informs`, `declares`, and `constrains`.
Graph validation emits `INTENT_GRAPH_EDGE_KIND_INVALID` when an edge kind is
not one of those runtime-supported Intent graph relationship kinds.

Input nodes make data dependencies explicit. Goal inputs are external values
available at goal start. Step inputs are required value ports for one step. A
step input must have exactly one incoming `data` edge from either a goal input
node or an earlier producing step. If multiple prior values have the same type,
the checker selects the nearest prior value in source order and emits the chosen
edge deterministically. Parameter data embedded in `Goal`, `Step`, `Input`,
`data`, and `requires` graph payloads retains the declaring parameter `span`.
Graph `data` edge payloads may also include `sourceSpan` and `targetSpan` for
the two bound parameters, while graph `requires` edge payloads may include
`targetSpan` for the required input parameter.
Graph `produces` edge payloads that connect the final executable step to
completion may include `sourceSpan` for the final step output type and
`targetSpan` for the goal output type.

Graph validation emits `INTENT_GRAPH_EDGE_UNRESOLVED` for any edge whose
`from` or `to` endpoint is absent from the same graph payload, emits
`INTENT_GRAPH_INPUT_UNBOUND` when a step `Input` node does not have exactly one
incoming `data` edge, emits `INTENT_GRAPH_GOAL_COMPLETION_INVALID` when a
`Goal` node lacks its `${goal_id}:completion` `Completion` node, lacks exactly
one outgoing `completes` edge to that node, or has `completes` edges to another
completion, emits `INTENT_GRAPH_COMPLETION_INVALID` when a
`Completion` node does not have exactly one incoming `completes` edge from a
`Goal`, exactly one incoming `produces` edge from a `Step`, at least one
incoming `verifies` edge from a `Check` node, or a `guards` edge count that
does not match the goal's `Invariant` nodes, and emits `INTENT_GRAPH_CYCLE` for
cyclic graph edges. Graph validation emits `INTENT_GRAPH_GUARD_INVALID` when
an `Invariant` node is missing its `guards` edge to `Completion` or to any
`Effect`, `Checkpoint`, or step-scoped `Check` node in the same goal.
Graph validation emits `INTENT_GRAPH_AUTHORIZATION_INVALID` when an `Effect`
node or verification `Check` node with `data.effect` lacks an incoming
`authorizes` edge from a `Capability`, or when its incoming `authorizes` edge is
not from a `Capability`.
Graph validation emits `INTENT_GRAPH_EFFECT_REQUEST_INVALID` when an `Effect`
node lacks exactly one incoming `requests` edge from its owning `Step`, or when
any incoming `requests` edge is not from that owning `Step`.
Graph validation emits `INTENT_GRAPH_STEP_SEQUENCE_INVALID` when a goal with
multiple `Step` nodes does not have exactly one linear `precedes` chain across
those steps, or when the `Step` producing `Completion` is not the tail step of
that chain.
Graph validation emits `INTENT_GRAPH_STEP_ATTACHMENT_INVALID` when a
step-scoped `Check` lacks a `requires` edge to its owning `Step`, an `Approval`
lacks an `approves` edge to its owning `Step` or to an approval-required
`Effect` in that same step, a `Checkpoint` lacks a `checkpoints` edge from its
owning `Step`, or a `Policy` lacks its `timeouts` or `retries` edge to its
owning `Step`.

The next static graph contract milestone is rejection, not repair. Static graph
validators must reject any graph with a missing or unsupported
`schema_version` or `ast_schema_version`, missing, non-string, or blank
`source` or `package` provenance, whose `ok` value is not `true`, whose
schema-level structural strings are empty, whose runtime structural strings are
blank after trimming, whose node or edge kind is outside the supported sets
above, whose edge endpoint does not resolve inside the same payload, whose
`Capability` nodes omit valid runtime approval-policy data, whose `Memory`
nodes omit valid runtime retention lifecycle data, whose `Policy` nodes omit
valid runtime step execution policy data, whose `Approval` nodes omit valid
runtime step gate data, or whose required
execution, data, authorization, approval, guard, verification, completion, and
step-attachment relationships fail graph validation. Blank envelope provenance
emits `INTENT_GRAPH_ENVELOPE_INVALID` before collection, node, or edge
semantic validation so graph ids, diagnostics, and package-scoped runtime
contracts keep stable origins. Malformed graphs may be emitted for diagnostics,
but they are never executable runtime contracts.

Memory nodes carry raw `retention` lines plus structured `retentionRules`
parsed from `retain ... until ...` lines. Runtime validation requires
`data.retention` to be an array, `data.retentionRules` to be a non-empty array,
and every retention rule to include non-empty `raw`, `subject.raw`, and
`until.raw` strings. The supported graph lifecycle values are `goal_complete`,
`goal.completed`, or bounded durations such as `30d`. A graph with a
`Memory` node that omits or malforms those lifecycle fields emits
`INTENT_GRAPH_MEMORY_INVALID` and is non-executable. Source checking still emits
`INTENT_MEMORY_UNSCOPED` for memory blocks with no parsed retention rules and
`INTENT_MEMORY_RETENTION_INVALID` for unsupported lifecycle targets before graph
execution is considered.

Context nodes carry the same structured source call data as `ContextDecl`:
`source`, `args`, `argKinds`, `argSpans`, `expression`, and `trust`. Repo, doc,
and file context nodes use trusted local trust metadata. Web context nodes and
browser/page state use untrusted external trust metadata. Runtime validation
requires every `Context` node trust record to carry zone `trusted`,
`untrusted`, or `unknown`, a non-empty `source`, and an optional non-empty
`argument`; malformed records emit `INTENT_GRAPH_TRUST_INVALID`.

Effect nodes carry normalized effect call data: `family`, `action`, `args`,
`argKinds`, `argSpans`, `expression`, and trust metadata when applicable.
Verification shell `Check` nodes carry the same effect data under
`data.effect`, so diagnostics can point to the exact denied command argument.
Runtime validation requires `Effect` node trust and verification `Check`
`data.effect.trust` records to use the same trust shape as `Context` nodes.
Missing or malformed trust metadata emits `INTENT_GRAPH_TRUST_INVALID` and
makes the graph non-executable because runtime trust sinks must not infer trust
for effect execution.

Capability nodes carry normalized grants and any approval policy parsed from
the capability block. A body line of `approval required` is represented as
`data.approvalPolicy: "required"` on the `Capability` node. Each structured
entry in `data.grants` carries the source `span` of its grant line, so
capability authorization, diagnostics, and runtime provenance can point to the
grant that authorized an effect or context source.
Capability nodes are also runtime policy inputs. Graph validation requires
`data.family` to be non-empty, `data.approvalPolicy` to be either `none` or
`required`, and `data.grants` to be an array. Malformed capability policy data
emits `INTENT_GRAPH_CAPABILITY_INVALID` and makes the graph non-executable
because runtime authorization and approval enforcement must not infer missing
policy.

Step requirement nodes are `Check` nodes scoped to one owning step. They create
`requires` edges into that step and `gates` edges to the owning goal. They are
not completion checks and must not create `verifies` edges to the goal
`Completion` node.

Step checkpoint nodes are `Checkpoint` nodes scoped to one owning step. The
owning step node lists them in its `data.checkpoints` array, and each
checkpoint has one incoming `checkpoints` edge from that owning step.
Checkpoint graph data must carry non-empty `data.checkpoint` and non-empty
`data.ownerStep`; malformed checkpoint records are non-executable because graph
validation must emit `INTENT_GRAPH_CHECKPOINT_INVALID`. Source checkpoint
labels must also be non-empty after trimming; a source checkpoint with an empty
label is non-executable because the checker must emit `INTENT_CHECKPOINT_INVALID`.

Step approval nodes are `Approval` nodes scoped to one owning step. The owning
step node lists them in its `data.approvals` array, and each approval has one
outgoing `approves` edge to that owning step. When an effect in that step is
authorized by a capability whose approval policy is `required`, a step
`Approval` node also has an outgoing `approves` edge to that approval-required
`Effect` node. Approval labels must be non-empty after trimming; a graph with an
empty approval label is non-executable because the checker must emit
`INTENT_APPROVAL_INVALID`. Runtime graph validation also requires each
`Approval` node to carry non-empty `data.approval` and non-empty
`data.ownerStep`; malformed approval node payloads emit
`INTENT_GRAPH_APPROVAL_INVALID` and are non-executable.

Step policy nodes are `Policy` nodes scoped to one owning step. The owning step
node lists timeout summaries in `data.timeouts` and retry summaries in
`data.retries`. Each timeout policy has one outgoing `timeouts` edge to that
owning step, and each retry policy has one outgoing `retries` edge to that
owning step. Runtime graph validation also requires `data.policyKind` to be
`timeout` or `retry`, `data.policy` to be non-empty, and `data.ownerStep` to be
non-empty; malformed records emit `INTENT_GRAPH_POLICY_INVALID` and make graph
output non-executable.

Git commits are represented as `Effect` nodes the same way as other effect
requests. The node data records family `git`, action `commit`, the normalized
`message` argument, and the original expression. When covered, graph output
creates an `authorizes` edge from the matching `Capability` node to the
`GitCommit` `Effect` node.

Secret reads are represented as `Effect` nodes the same way as other effect
requests. The node data records family `secret`, action `read`, the normalized
`name` argument, and unknown trust metadata. This is a Phase 2 static-model
coverage check only; graph output must not contain secret values.

Ticket updates are represented as `Effect` nodes the same way as other effect
requests. The node data records family `ticket`, action `update`, the
normalized `id` argument, and the original expression. When covered, graph
output creates an `authorizes` edge from the matching `Capability` node to the
`TicketUpdate` `Effect` node.

Deploys are represented as `Effect` nodes the same way as other effect
requests. The node data records family `deploy`, action `deploy`, the
normalized `target` argument, and the original expression. When covered, graph
output creates an `authorizes` edge from the matching `Capability` node to the
`Deploy` `Effect` node.

Each goal has exactly one `Completion` node. The goal creates a `completes` edge
to the completion node. Required checks create `verifies` edges to completion.
Invariants that apply to the goal create `guards` edges to completion and to
every effect, checkpoint, and step requirement check in that goal. The last
executable step in the plan creates a `produces` edge to completion. That edge
may carry `data.sourceSpan` for the final step output type and
`data.targetSpan` for the goal output type. Graph validation emits
`INTENT_GRAPH_GOAL_COMPLETION_INVALID` when a `Goal` node lacks its
`${goal_id}:completion` `Completion` node, lacks exactly one outgoing
`completes` edge to that node, or has `completes` edges to another completion.
Graph validation emits
`INTENT_GRAPH_COMPLETION_INVALID` unless each `Completion` node has exactly one
incoming `completes` edge from a `Goal` and exactly one incoming `produces` edge
from a `Step`, at least one incoming `verifies` edge from a `Check` node, and a
`guards` edge count that matches the goal's `Invariant` nodes. Graph validation
emits `INTENT_GRAPH_EFFECT_REQUEST_INVALID` when an `Effect` node lacks exactly
one incoming `requests` edge from its owning `Step`, or when any incoming
`requests` edge is not from that owning `Step`. Graph validation
emits `INTENT_GRAPH_GUARD_INVALID` when an `Invariant` node is missing its
`guards` edge to `Completion` or to any `Effect`, `Checkpoint`, or step-scoped
`Check` node in the same goal. Completion is reachable only when all incoming
completion edges have succeeded or remained unviolated.

The runtime must treat the graph as authoritative: it may execute only graph
nodes, may invoke only authorized effects, must preserve guard and approval
edges, and must record provenance back to the source span for every final
output. When an output is authorized by a capability grant, provenance should
prefer the grant object's `span` over the enclosing `Capability` node span.
