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
- `MemoryDecl`: scoped state or retained evidence with lifecycle rules.
- `PlanBlock`: ordered list of executable steps.
- `StepDecl`: typed inputs, output, declared effects, timeout, retry policy,
  checks, and body expression.
- `VerifyBlock`: required or advisory completion checks.
- `InvariantBlock`: always-on rules evaluated across effects and checkpoints.
- `EffectDecl`: reusable typed effect signature.
- `PolicyDecl`: trust, denial, approval, and flow rules.
- `TypeDecl`: record, enum, alias, union, or generic type declaration.
- `Expr`: literals, names, field access, calls, lists, records, conditionals,
  matches, lets, returns, assignments, and effect requests.
- `TypeRef`: named, generic, record, list, map, optional, or union type use.

The prototype may parse unsupported nodes into `UnknownDecl` or `UnknownExpr`
only when it also emits a blocking diagnostic.

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
- Generated graph nodes keep `source_id` and `span` from the AST node that
  caused them.

## Checker Responsibilities

The checker consumes a complete AST and produces either a checked model or
blocking diagnostics.

- Bind package, imports, declarations, block-local names, step inputs, and goal
  state without implicit globals.
- Type check expressions, inputs, outputs, context values, state values, step
  results, verification predicates, and effect arguments.
- Reject undeclared effects and effect calls not covered by an in-scope
  capability.
- Normalize and compare constrained resources such as paths, commands, domains,
  branches, secret names, and approval targets.
- Require verification gates for every goal and ensure they are pure unless
  they declare a verification effect.
- Enforce invariant placement and attach invariants to the graph as guards.
- Reject unsafe trust flows, including untrusted data flowing into executable
  commands, write targets, secrets, or approval decisions without policy.
- Require memory and checkpoint state to be scoped, serializable, and assigned a
  retention lifecycle.
- Build dependency edges from step inputs, produced values, checks, approvals,
  checkpoints, and completion gates.
- Reject execution cycles unless a future bounded-loop form declares progress.

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
- `INTENT_TYPE_MISMATCH`
- `INTENT_EFFECT_UNDECLARED`
- `INTENT_CAPABILITY_DENIED`
- `INTENT_VERIFY_MISSING`
- `INTENT_VERIFY_IMPURE`
- `INTENT_INVARIANT_VIOLATION`
- `INTENT_TRUST_FLOW_UNSAFE`
- `INTENT_MEMORY_UNSCOPED`
- `INTENT_GRAPH_CYCLE`

Errors block graph emission. Warnings and notes may be emitted with a checked
graph when runtime behavior remains unambiguous.

## Execution Graph Shape

The first prototype emits JSON with deterministic ordering by source order, then
node id. It is an intermediate contract for a local runtime, not a public API.

```json
{
  "version": 1,
  "source": {
    "root": "intent/examples/demo.intent",
    "package": "examples.demo"
  },
  "nodes": [
    {
      "id": "goal.ship_checkout_fix",
      "kind": "goal",
      "name": "ship_checkout_fix",
      "inputs": [{ "name": "ticket", "type": "TicketRef" }],
      "output": { "type": "PullRequest" },
      "source_id": "ast.4",
      "span": "loc.4"
    },
    {
      "id": "capability.tests",
      "kind": "capability",
      "family": "shell",
      "action": "exec",
      "constraints": { "commands": ["npm test"] },
      "source_id": "ast.7",
      "span": "loc.7"
    },
    {
      "id": "step.run_tests",
      "kind": "step",
      "name": "run_tests",
      "inputs": [{ "name": "patch", "type": "GitDiff" }],
      "output": { "type": "ShellExecResult" },
      "effects": ["ShellExec"],
      "source_id": "ast.15",
      "span": "loc.15"
    },
    {
      "id": "check.tests_pass",
      "kind": "check",
      "mode": "required",
      "predicate": "run_tests.exit_code == 0",
      "source_id": "ast.19",
      "span": "loc.19"
    }
  ],
  "edges": [
    {
      "from": "goal.ship_checkout_fix",
      "to": "step.run_tests",
      "kind": "requires"
    },
    {
      "from": "capability.tests",
      "to": "step.run_tests",
      "kind": "authorizes",
      "effect": "ShellExec"
    },
    {
      "from": "step.run_tests",
      "to": "check.tests_pass",
      "kind": "verifies"
    }
  ],
  "diagnostics": []
}
```

Required node kinds are `goal`, `context`, `capability`, `memory`, `step`,
`effect`, `check`, `invariant`, `approval`, `checkpoint`, and `completion`.

Required edge kinds are `requires`, `produces`, `authorizes`, `verifies`,
`guards`, `approves`, `checkpoints`, and `completes`.

The runtime must treat the graph as authoritative: it may execute only graph
nodes, may invoke only authorized effects, must preserve guard and approval
edges, and must record provenance back to the source span for every final
output.
