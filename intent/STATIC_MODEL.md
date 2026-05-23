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
- `EffectCall`: parsed effect request with callee, arguments, source span, and
  raw text.
- `PolicyDecl`: trust, denial, approval, and flow rules.
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
- Generated graph nodes keep `source_id` and `span` from the AST node that
  caused them.

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
- Type check expressions, inputs, outputs, context values, state values, step
  results, verification predicates, and effect arguments.
- Reject undeclared effects and effect calls not covered by an in-scope
  capability.
- Check simple capability constraints for file paths and shell commands.
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
  milestone only checks literal file path and shell command arguments.
- Unknown identifiers in effect arguments are allowed to remain unresolved only
  when the effect call is not used for a capability-constrained resource.

## Capability Constraints

The first constraint checker supports only direct string-literal matches for
file paths and shell commands. A capability authorizes an effect call when the
effect family matches and every constrained argument is covered by the
capability.

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
- Non-literal shell command arguments are denied.

When no in-scope capability covers a constrained resource, the checker emits
`INTENT_CAPABILITY_DENIED` at the effect call span with the denied argument,
denied value, and allowed grants.

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
