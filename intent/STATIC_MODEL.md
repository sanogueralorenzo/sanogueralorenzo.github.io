# Intent Static Model

Phase 2 turns the written language contract into a parsed, checked, and
machine-readable model. This note defines the first prototype shape only; it
does not try to settle the full language.

## AST Nodes

Every node carries a stable `id`, `kind`, `span`, and optional `name`.

- `PackageDecl`: package path for a source file.
- `ImportDecl`: imported package or symbol path.
- `GoalDecl`: root executable unit, inputs, output, clauses, and body blocks.
- `ContextDecl`: named source of truth, resource expression, freshness policy,
  and access mode.
- `CapabilityDecl`: named permission grant with family, action, constraints,
  and optional approval requirement.
- `MemoryDecl`: scoped state or retained evidence with one or more retention
  lifecycle rules.
- `MemoryRetention`: structured `retain ... until ...` rule with retained
  subject, until condition, raw text, and source span.
- `PlanBlock`: ordered list of executable steps.
- `StepDecl`: typed inputs, output, step-local requirements, step approval
  gates, step checkpoint statements, step policy statements, declared effects,
  checks, and body expression.
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
- `EffectCall`: parsed effect request with callee, arguments, source span, and
  raw text.
- `PolicyDecl`: trust, denial, approval, and flow rules.
- `TrustMark`: checker-owned trust metadata for a value, effect argument, graph
  node, or graph edge.
- `TypeDecl`: record, enum, alias, union, or generic type declaration.
- `Expr`: literals, names, field access, calls, lists, records, conditionals,
  matches, lets, returns, assignments, and effect requests.
- `TypeRef`: named, generic, record, list, map, optional, or union type use.

The prototype may parse unsupported nodes into `UnknownDecl` or `UnknownExpr`
only when it also emits a blocking diagnostic.

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
        "outputType": "PullRequest"
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
        "outputType": "PullRequest"
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
`package`, `ok`, `diagnostics`, `nodes`, and `edges`. Node ids are stable within
one graph payload. Edge endpoints must refer to node ids emitted in the same
payload. The graph command may emit `ok: false` with diagnostics for inspection,
but runtimes must treat that graph as non-executable.

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
  `intent.graph.v0.schema.json` and has `ok: true`.

## Checker Responsibilities

The checker consumes a complete AST and produces either a checked model or
blocking diagnostics.

- Bind package, imports, declarations, block-local names, step inputs, and goal
  state without implicit globals.
- Reject duplicate type names in the file, duplicate goal names in the file,
  duplicate goal input names in a goal, duplicate step names in a goal, and
  duplicate step input names in a step.
- Resolve every type reference against built-ins and file-local type
  declarations.
- Bind step inputs against goal inputs and earlier step outputs in source order.
- Assign first-prototype trust zones to source values. Web contexts are
  untrusted; literals and checker-approved policy outputs are trusted.
- Type check expressions, inputs, outputs, context values, state values, step
  results, verification predicates, and effect arguments.
- Reject undeclared effects and effect calls not covered by an in-scope
  capability.
- Check simple capability constraints for file paths, shell commands, web/http
  read domains, and git push branches or remotes.
- Normalize and compare constrained resources such as paths, commands, domains,
  branches, secret names, and approval targets.
- Require verification gates for every goal and ensure they are pure assertions
  except for supported verification effects.
- Bind verification shell requirements to declared shell run capability grants.
- Emit `INTENT_VERIFY_IMPURE` for side-effect calls inside goal-level `verify`
  requirements, including file writes, git pushes, web or HTTP reads, deploys,
  and ticket updates.
- Parse step-body `require ...` lines as step requirements, separate from
  goal-level verification requirements.
- Parse step-body `approval ...` lines as step approval gates owned by their
  containing step.
- Parse step-body `checkpoint ...` lines as step checkpoints owned by their
  containing step.
- Parse step-body `timeout ...` and `retry ...` lines as step policy statements
  owned by their containing step.
- Enforce invariant placement, emit invariant statements as `Invariant` nodes,
  and attach those nodes to the graph as guards.
- Reject unsafe trust flows, including untrusted data flowing into executable
  commands, write targets, secrets, or approval decisions without policy.
- Emit `INTENT_TRUST_FLOW_UNSAFE` for nonliteral shell command arguments that
  are not already trusted by the checker.
- Require memory and checkpoint state to be scoped, serializable, and assigned a
  retention lifecycle.
- Emit `INTENT_MEMORY_UNSCOPED` when a memory block has no parsed
  `retain ... until ...` retention rule.
- Build dependency edges from step inputs, produced values, checks, approvals,
  checkpoints, policies, and completion gates.
- Emit step requirements as `Check` nodes with `requires` edges into the owning
  step and `gates` edges to the owning goal.
- Emit step approval gates as `Approval` nodes, list them on the owning `Step`
  node data, and connect each one with an `approves` edge from that `Approval`
  node to the owning `Step`.
- Emit step checkpoints as `Checkpoint` nodes, list them on the owning `Step`
  node data, and connect each one with a `checkpoints` edge from that `Step`.
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
- There are no implicit conversions, field projections, destructuring, or
  forward references.
- If no prior value has the required type, the checker emits
  `INTENT_STEP_INPUT_UNRESOLVED`.

Every successful binding is also emitted as graph data dependency:

- Each goal input becomes an `input` graph node with `scope: "goal"`.
- Each step input becomes an `input` graph node with `scope: "step"` and the
  owning step id.
- A step input bound to a goal input creates a `data` edge from the goal input
  node to the step input node.
- A step input bound to an earlier step output creates a `data` edge from the
  producing step node to the step input node.
- A step input node creates a `requires` edge to its owning step, so execution
  waits for the bound value before the step can run.

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
  "raw": "shell.exec(command: \"npm test\")",
  "span": "loc.21"
}
```

Rules:

- Positional and named arguments are retained in source order.
- Literal string, number, and boolean values are normalized for checking while
  retaining raw token spans.
- Nested calls may be parsed as argument values, but the first capability
  milestone only checks literal file path, shell command, web/http read URL or
  domain, and git push branch or remote arguments.
- Unknown identifiers in effect arguments are allowed to remain unresolved only
  when the effect call is not used for a capability-constrained resource or a
  trust-sensitive resource.

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
- Step approval gates do not create `verifies` edges to the goal `Completion`
  node and do not replace capability policy approval requirements.

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
- Step checkpoints do not create `verifies` edges to the goal `Completion`
  node and do not replace memory retention rules.

## Step Policies

Step bodies may contain `timeout ...` and `retry ...` lines that declare
execution policy for only that step:

```intent
plan {
  step run_tests(patch: GitDiff) -> TestReport {
    timeout 2m
    retry max_attempts: 3, backoff: exponential
  }
}
```

Rules:

- Step-body timeout and retry lines are parsed into the owning `StepDecl` as
  step policy statements.
- `timeout` preserves the raw duration text; `retry` preserves the raw policy
  text.
- Each step policy emits one graph `Policy` node whose span is the policy line.
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
- A malformed `retain` line emits `INTENT_MEMORY_RETENTION_INVALID`.
- Retention entries are checker-owned lifecycle data, not opaque comments.
- The graph builder emits `retentionRules` in the owning `Memory` node data so
  runtimes can enforce retention without reparsing memory body text.

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
file paths, shell commands, web/http read domains, and git push branches or
remotes. A capability authorizes an effect call when the effect family matches
and every constrained argument is covered by the capability.

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
`INTENT_CAPABILITY_DENIED` at the effect call span with the denied argument,
denied value, and allowed grants.

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
- A verification shell request is valid only when an in-scope capability grants
  shell `run` for the normalized command.
- A successful binding creates an `authorizes` edge from the matching
  `Capability` node to the `Check` node.
- If no declared shell run grant covers the command, the checker emits
  `INTENT_VERIFY_UNDECLARED` at the verification shell call span with the
  denied command and allowed shell run grants.

## Verification Purity

Goal-level `verify` requirements are completion assertions, not execution
steps. They may use predicate logic and supported verification effects only.
The supported verification effect for this milestone is a shell check written
as `shell("...")` or `shell(command: "...")`; it remains subject to
verification shell binding and capability checks.

Any side-effecting operation inside a goal-level `verify` requirement is
impure. Calls such as `FileWrite`, `GitPush`, `web.read`, `http.get`, deploy
operations, or ticket updates emit `INTENT_VERIFY_IMPURE` at the impure call
span and make graph output non-executable.

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
- `INTENT_UNSUPPORTED_SYNTAX`
- `INTENT_NAME_UNRESOLVED`
- `INTENT_NAME_DUPLICATE`
- `INTENT_TYPE_UNRESOLVED`
- `INTENT_TYPE_MISMATCH`
- `INTENT_STEP_INPUT_UNRESOLVED`
- `INTENT_EFFECT_UNDECLARED`
- `INTENT_CAPABILITY_DENIED`
- `INTENT_VERIFY_MISSING`
- `INTENT_VERIFY_IMPURE`
- `INTENT_VERIFY_UNDECLARED`
- `INTENT_INVARIANT_VIOLATION`
- `INTENT_TRUST_FLOW_UNSAFE`
- `INTENT_MEMORY_UNSCOPED`
- `INTENT_MEMORY_RETENTION_INVALID`
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
        "parameters": [{ "name": "ticket", "type": "TicketRef" }],
        "outputType": "PullRequest"
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
      "id": "goal:ship_checkout_fix:capability:0",
      "kind": "Capability",
      "label": "tests",
      "span": "loc.7",
      "data": {
        "family": "shell",
        "action": null,
        "grants": [{ "action": "run", "key": "command", "value": "npm test" }]
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
        "inputs": [{ "name": "ticket", "type": "TicketRef" }],
        "outputType": "GitDiff",
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
        "inputs": [{ "name": "patch", "type": "GitDiff" }],
        "outputType": "ShellExecResult",
        "effects": ["ShellExec"],
        "approvals": ["release_manager_review"],
        "requirements": [],
        "checkpoints": ["test_report_written"],
        "timeouts": ["2m"],
        "retries": ["max_attempts: 3, backoff: exponential"]
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
      "label": "max_attempts: 3, backoff: exponential",
      "span": "loc.16",
      "data": {
        "scope": "step",
        "ownerStep": "run_tests",
        "policyKind": "retry",
        "policy": "max_attempts: 3, backoff: exponential"
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
      "label": "run_tests.exit_code == 0",
      "span": "loc.19",
      "data": {}
    },
    {
      "id": "goal:ship_checkout_fix:completion",
      "kind": "Completion",
      "label": "ship_checkout_fix",
      "span": "loc.4",
      "data": {
        "outputType": "PullRequest"
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
        "trust": { "zone": "unknown" }
      }
    },
    {
      "from": "goal:ship_checkout_fix:step:prepare_patch:input:ticket",
      "to": "goal:ship_checkout_fix:step:prepare_patch",
      "kind": "requires",
      "data": { "parameter": "ticket", "type": "TicketRef" }
    },
    {
      "from": "goal:ship_checkout_fix:step:prepare_patch",
      "to": "goal:ship_checkout_fix:step:run_tests:input:patch",
      "kind": "data",
      "data": {
        "parameter": "patch",
        "type": "GitDiff",
        "trust": { "zone": "unknown" }
      }
    },
    {
      "from": "goal:ship_checkout_fix:step:run_tests:input:patch",
      "to": "goal:ship_checkout_fix:step:run_tests",
      "kind": "requires",
      "data": { "parameter": "patch", "type": "GitDiff" }
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

Required edge kinds are `data`, `requires`, `produces`, `authorizes`,
`verifies`, `guards`, `gates`, `approves`, `checkpoints`, `timeouts`,
`retries`, `completes`, `plans`, `precedes`, `requests`, `supplies`,
`informs`, `declares`, and `constrains`.

Input nodes make data dependencies explicit. Goal inputs are external values
available at goal start. Step inputs are required value ports for one step. A
step input must have exactly one incoming `data` edge from either a goal input
node or an earlier producing step. If multiple prior values have the same type,
the checker selects the nearest prior value in source order and emits the chosen
edge deterministically.

Memory nodes carry raw `retention` lines plus structured `retentionRules`
parsed from `retain ... until ...` lines. A graph with a `Memory` node that
lacks retention lifecycle data is non-executable because the checker must emit
`INTENT_MEMORY_UNSCOPED`.

Step requirement nodes are `Check` nodes scoped to one owning step. They create
`requires` edges into that step and `gates` edges to the owning goal. They are
not completion checks and must not create `verifies` edges to the goal
`Completion` node.

Step checkpoint nodes are `Checkpoint` nodes scoped to one owning step. The
owning step node lists them in its `data.checkpoints` array, and each
checkpoint has one incoming `checkpoints` edge from that owning step.

Step approval nodes are `Approval` nodes scoped to one owning step. The owning
step node lists them in its `data.approvals` array, and each approval has one
outgoing `approves` edge to that owning step.

Step policy nodes are `Policy` nodes scoped to one owning step. The owning step
node lists timeout summaries in `data.timeouts` and retry summaries in
`data.retries`. Each timeout policy has one outgoing `timeouts` edge to that
owning step, and each retry policy has one outgoing `retries` edge to that
owning step.

Each goal has exactly one `Completion` node. The goal creates a `completes` edge
to the completion node. Required checks create `verifies` edges to completion.
Invariants that apply to the goal create `guards` edges to completion and to
every effect, checkpoint, and step requirement check in that goal. The last
executable step in the plan creates a `produces` edge to completion. Completion
is reachable only when all incoming completion edges have succeeded or remained
unviolated.

The runtime must treat the graph as authoritative: it may execute only graph
nodes, may invoke only authorized effects, must preserve guard and approval
edges, and must record provenance back to the source span for every final
output.
