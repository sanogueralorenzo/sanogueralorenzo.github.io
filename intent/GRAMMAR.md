# Intent Grammar Note

This note defines the first parser milestone for the Phase 2 static model. It is
intentionally small: parse declarations, preserve spans, and leave expression
semantics to later checker work.

## Scope

The parser must accept:

- Package declarations.
- Top-level type declarations.
- Goal declarations.
- `context`, `capability`, `memory`, `plan`, `verify`, and `invariant` blocks.
- Step declarations inside `plan`, including step-local requirements,
  approval gates, checkpoints, retry policies, and timeouts.
- `require` and `deny` statements.
- Context and effect call arguments in simple call expressions.
- Line comments.
- String literals.
- Identifiers.

The parser must reject unsupported top-level declarations instead of treating
them as opaque text.

## File Shape

```ebnf
file           = spacing, package_decl, spacing, { import_decl, spacing },
                 { top_level_decl, spacing },
                 eof ;
top_level_decl = type_decl | goal_decl ;
package_decl   = "package", s, package_name, line_end ;
import_decl    = "import", s, import_path, line_end ;

type_decl      = "type", s, type_name, [ ws, "=", ws, raw_type_def ],
                 line_end ;

goal_decl      = "goal", s, ( string | goal_signature ), ws, block ;
goal_signature = identifier, [ params ], [ ws, "->", ws, type_ref ] ;
block          = "{", ws, { goal_item, ws }, "}" ;
goal_item      = context_block
               | capability_block
               | memory_block
               | plan_block
               | verify_block
               | invariant_block ;
```

Milestone files contain exactly one package declaration before any other
declarations. Import declarations may follow the package and precede type or
goal declarations. More than one import, type, or goal may appear in a file.

Import declarations are path-only in the first prototype. The parser preserves
the imported package or symbol path and source span, but imports do not
contribute types or declarations to checker scope yet.

Type declarations are line-based in the first prototype. The optional
definition is preserved as raw text and is not parsed into record fields,
aliases, enum cases, or generic parameters yet.

Goal signature params are goal inputs. The parser preserves their source order,
names, types, and parameter spans so the checker can emit graph input nodes,
data dependency edges, and duplicate parameter diagnostics at the parameter
span.

## Goal Blocks

```ebnf
context_block    = "context", s, call_expr, line_end ;
capability_block = "capability", s, identifier, ws, "{", ws,
                   { capability_stmt, ws }, "}" ;
capability_stmt  = capability_approval_stmt
                 | capability_grant_stmt
                 | raw_capability_stmt ;
capability_approval_stmt = "approval", s, "required", line_end ;
capability_grant_stmt = capability_line_grant_stmt
                      | capability_call_grant_stmt ;
capability_line_grant_stmt = identifier_path, s, [ grant_arg, { s, grant_arg } ],
                             line_end ;
capability_call_grant_stmt = call_expr, line_end ;
grant_arg       = identifier, ws, ":", ws, arg_value ;
raw_capability_stmt = raw_text_until_terminator, line_end ;
memory_block     = "memory", s, identifier, ws, "{", ws,
                   { memory_stmt, ws }, "}" ;
memory_stmt      = retain_stmt | memory_key_stmt | raw_memory_stmt ;
retain_stmt      = "retain", s, retain_subject, s, "until", s,
                   retain_until, line_end ;
memory_key_stmt  = "key", s, identifier, [ ws, ":", ws, type_ref ],
                   line_end ;
retain_subject   = raw_text_until_until_keyword ;
retain_until     = raw_text_until_terminator ;
raw_memory_stmt  = raw_text_until_terminator, line_end ;
plan_block       = "plan", ws, "{", ws, { step_decl, ws }, "}" ;
verify_block     = "verify", ws, "{", ws, { require_stmt, ws }, "}" ;
invariant_block  = "invariant", ws, "{", ws, { invariant_stmt, ws }, "}" ;

require_stmt     = "require", s, raw_expr, line_end ;
deny_stmt        = "deny", s, raw_expr, line_end ;
invariant_stmt   = require_stmt | deny_stmt ;
```

`context` is a single-line declaration in this milestone. The `context <call>`
form preserves the parsed call as structured source data: source name, ordered
arguments, argument kinds, argument source spans, original expression text, and
checker-owned trust zone/source. Context declarations that describe repo
resources are treated as
trusted local sources by the first checker prototype and are not
capability-enforced yet. Structured `context web(...)` declarations are treated
as untrusted external sources and must be covered by an in-scope
`web read domain` capability. Structured `context documents(...)` declarations
are treated as trusted local sources and must be covered by an in-scope
`file read path` capability. If no matching capability covers a structured web
or documents context source, the checker emits `INTENT_CONTEXT_UNDECLARED`.
`capability` bodies are parsed as statement lists whose items are preserved as
raw spanned lines. Grant lines such as `read path: "./src/**"` and parsed dotted
grant calls such as `git.commit(message: "ship fix")` are also retained as
structured grant objects. Each structured grant object must carry a `span` for
the exact grant line, an `actionSpan`, and ordered `args` entries with key,
value, kind, key span, value span, and full argument span. Multi-argument grants
such as `push branch: "main" remote: "origin"` stay as one grant with multiple
argument records, so AST output, graph `Capability` node `grants`, and
diagnostics/provenance can point to the grant or constrained argument instead
of only the surrounding capability block. A capability body may contain
`approval required`; the
checker treats effects authorized by that capability as requiring a step-local
`approval ...` gate. `memory` bodies are parsed as statement lists, every
`key ...` line is parsed into structured key metadata, and every `retain ...
until ...` line is additionally parsed into structured `retentionRules` data
with a retained subject span and an until-condition span.
The checker accepts retention lifecycle targets only when the `until` value is
`goal_complete`, `goal.completed`, or a simple duration such as `30d`, `12h`,
`45m`, or `10s`.
`plan` accepts only `step` declarations. Step bodies accept only `effect`,
`require`, `approval`, `checkpoint`, `timeout`, `retry`, and `memory` lines.
`verify` accepts only `require`; `invariant` accepts `require` and `deny`.
Any other non-empty line in those strict blocks is retained as unsupported
syntax and emits `INTENT_UNSUPPORTED_SYNTAX` at that statement span instead of
being ignored.

Each `require ...` or `deny ...` line inside an `invariant` block is parsed as
an invariant statement with assertion polarity preserved. The graph builder
emits each invariant statement as an `Invariant` node and creates `guards`
edges from that node to the goal completion node and to every effect, step
checkpoint, and step requirement check in the same goal. This keeps always-on
rules visible across side effects and recovery boundaries. The enforced
invariant rules are currently deny rules: `deny production_deploy`, which rejects
`Deploy` effects targeting `production`; `deny secret_write`, which rejects
file write effects whose path or name looks like a secret, for example `.env`,
`secret`, `token`, `credential`, `key`, or `password`; and
`deny unrelated_file_write`, which rejects file write effects whose path is
outside declared `repo(...)` context roots. Each emits
`INTENT_INVARIANT_VIOLATION` at the invariant line span.

Every `memory` block must include at least one `retain ... until ...` retention
rule. A memory block without a parsed retention rule is syntactically valid, but
the checker emits `INTENT_MEMORY_UNSCOPED` because the retained state has no
declared lifecycle. A parsed retention rule with an unsupported `until` value
emits `INTENT_MEMORY_RETENTION_INVALID`.

## Steps

```ebnf
step_decl  = "step", s, identifier, [ params ], ws, "->", ws, type_ref,
             ( line_end | ws, step_body ) ;
step_body  = "{", ws, { step_item, ws }, "}" ;
step_item  = step_require_stmt
           | step_approval_stmt
           | step_checkpoint_stmt
           | step_timeout_stmt
           | step_retry_stmt
           | step_memory_stmt ;
step_require_stmt = "require", s, raw_expr, line_end ;
step_approval_stmt = "approval", s, raw_expr, line_end ;
step_checkpoint_stmt = "checkpoint", s, raw_expr, line_end ;
step_timeout_stmt = "timeout", s, duration, line_end ;
step_retry_stmt = "retry", s, raw_policy, line_end ;
step_memory_stmt = "memory", s, memory_access, s, memory_ref, line_end ;
memory_access = "read" | "write" | "cite" ;
memory_ref = identifier, [ ".", identifier ] ;
params     = "(", ws, [ param, { ws, ",", ws, param } ], ws, ")" ;
param      = identifier, ws, ":", ws, type_ref ;
type_ref   = identifier, { ws, type_suffix } ;
type_suffix = "<", ws, type_ref, { ws, ",", ws, type_ref }, ws, ">" ;
duration   = raw_text_until_terminator ;
raw_policy = raw_text_until_terminator ;
```

Step declarations may be signatures only or may include a body containing
step-local `require ...`, `approval ...`, `checkpoint ...`, `timeout ...`, and
`retry ...` lines. Effect bodies and execution statements are out of scope.
Step input names are local to the step signature; the checker binds inputs by
matching their type against goal inputs and previous step outputs in source
order. Each step param preserves its parameter span and becomes a step input
port in the checked graph.

`require ...` lines inside a step body are parsed as step requirements. They are
not goal-level `verify` checks and do not create completion verification gates.
The graph builder emits each step requirement as a `Check` node, creates a
`requires` edge from that `Check` node into the owning `Step`, and creates a
`gates` edge from that `Check` node to the owning `Goal`.

`approval ...` lines inside a step body are parsed as step approval gates. They
are not capability declarations or goal-level verification checks. The graph
builder emits each step approval gate as an `Approval` node, lists it on the
owning step node data, and creates an `approves` edge from that `Approval` node
to the owning `Step`. When an effect in the same step is authorized by a
capability with `approval required`, the checker also creates an `approves`
edge from a step `Approval` node to that approval-required `Effect` node. If no
step-local approval gate is present, the checker emits
`INTENT_APPROVAL_MISSING`. Approval gate labels must be non-empty after
trimming. An empty approval label, including `approval ""`, emits
`INTENT_APPROVAL_INVALID` at the approval line span and makes graph output
non-executable.

`checkpoint ...` lines inside a step body are parsed as step checkpoint
statements. They are not memory retention declarations and do not become
goal-level verification checks. The graph builder emits each step checkpoint as
a `Checkpoint` node, lists it on the owning step node data, and creates a
`checkpoints` edge from the owning `Step` to that `Checkpoint`. Checkpoint
labels must be non-empty after trimming. An empty checkpoint label, including
`checkpoint ""`, emits `INTENT_CHECKPOINT_INVALID` at the checkpoint line span
and makes graph output non-executable.

`timeout <duration>` and `retry <raw policy>` lines inside a step body are
parsed as step policy statements and represented on the owning `StepDecl`. The
checker accepts timeout values only as simple positive durations such as `10s`,
`5m`, `2h`, or `1d`, and accepts retry policies only as `max N` with a positive
integer. Invalid policy syntax emits `INTENT_POLICY_INVALID` at the policy line
span. The graph builder surfaces valid policies on the owning step node data,
emits each statement as a `Policy` node, and creates `timeouts` or `retries`
edges from that policy node to the owning `Step`.

`memory read <memory>[.<key>]`, `memory write <memory>[.<key>]`, and
`memory cite <memory>[.<key>]` lines inside a step body are parsed as
step-local memory access statements. The checker rejects references whose
memory name or scope is not declared in the goal with `INTENT_MEMORY_UNDECLARED`.
When a memory access names a key, that key must match a retained subject or
explicit `key` declaration in the referenced memory block; otherwise the
checker emits `INTENT_MEMORY_KEY_UNDECLARED`.
The graph builder emits `writes` edges from the owning `Step` to the `Memory`
node, and emits `reads` or `cites` edges from the `Memory` node to the owning
`Step`. These edges carry access metadata plus source and target spans so
runtime provenance can distinguish memory mutation, consumption, and citation.
When a goal requires `all_outputs_cited`, requires
`memory_provenance_complete`, or denies `uncited_external_claim`, the final
completion-producing step must contain at least one `memory cite ...`
statement. Missing final-step citation coverage emits
`INTENT_PROVENANCE_MISSING`. Each final-step citation must be backed by an
earlier `memory write` to the same memory target and key; missing backing
writes emit `INTENT_PROVENANCE_UNBACKED`.

When a goal requires `final_state_checkpointed` or
`checkpointed_final_state`, the final completion-producing step must contain at
least one `checkpoint ...` statement. When a goal denies
`uncheckpointed_irreversible_effect`, every irreversible effect must be
followed by a non-empty `checkpoint ...` later in goal source order. Missing
checkpoint coverage emits `INTENT_CHECKPOINT_MISSING`.

## Expressions

The parser preserves raw expression text for later phases, but it also parses
simple call expressions used for contexts, effects, and checks. This lets the
checker inspect context and effect arguments without evaluating the full
expression language.

```ebnf
call_expr = identifier_path, ws, "(", ws,
            [ call_arg, { ws, ",", ws, call_arg } ], ws, ")" ;
call_arg  = [ identifier, ws, ":", ws ], arg_value ;
arg_value = string | number | bool | identifier_path | call_expr ;
number    = [ "-" ], digit, { digit }, [ ".", digit, { digit } ] ;
bool      = "true" | "false" ;
raw_expr  = raw_text_until_terminator ;
raw_type_def = raw_text_until_terminator ;
```

Raw expressions must still preserve source spans and balanced string/comment
handling, so diagnostics can point at the original text. When a raw expression
contains a parseable call expression, the parser emits both the raw text and a
spanned `CallExpr` with the callee path, ordered arguments, optional argument
names, argument kinds, literal values, and nested call values.

The `intent.ast.v0` parser accepts comma-separated positional and named string
literals plus single-segment lowercase identifiers. Unsupported argument
syntax inside a parsed v0 call, including numbers, booleans, dotted
identifiers, and nested calls, is `INTENT_PARSE_ERROR`; those argument kinds
are reserved for the next schema version. Unsupported expression syntax outside
the call envelope remains raw text unless the surrounding grammar requires a
call expression.

Examples of parseable effect calls:

```intent
file.read(path: "intent/GRAMMAR.md")
file.write("intent/STATIC_MODEL.md")
shell.exec(command: "npm test")
web.read(url: "https://docs.example.com/guide")
http.get("https://api.example.com/status")
GitCommit(message: "ship fix")
git.commit(message: "ship fix")
git.push(branch: "main")
git.push(remote: "origin")
TicketUpdate(id: "CODE-123")
Deploy(target: "staging")
```

Inside `verify` requirements, `shell("npm test")` and
`shell(command: "npm test")` are parseable verification shell calls. The checker
binds them to declared shell run capability grants instead of treating them as
opaque predicate text. Verification shell calls preserve ordered args, argKinds,
and argSpans the same way as effect calls.

Goal-level `verify` requirements are pure assertions by default. A `verify`
requirement may include only predicate logic and supported verification effects,
currently `shell("...")` and `shell(command: "...")`. Side-effect calls inside
`verify`, including file writes, git commits, git pushes, web or HTTP reads,
deploys, and ticket updates, are invalid and emit `INTENT_VERIFY_IMPURE`.

Constrained effect sink arguments are trust-sensitive in the first checker
prototype. A shell command, file write path, secret name, ticket id, deploy
target, git push ref, or git commit message must be either a string literal or
a value already marked trusted by the checker. Nonliteral constrained sink
expressions that are not trusted produce `INTENT_TRUST_FLOW_UNSAFE` rather
than being treated as opaque trusted strings.

Effect adapter calls are normalized by the v0 effect contract registry before
capability matching and graph emission. The registry currently covers file
read/write, shell run, web read, git push, git commit, secret read, ticket
update, and deploy adapter aliases. Unknown or custom effect calls continue to
use fallback family/action parsing until a later adapter schema makes custom
contracts explicit. The registry is also emitted as
`intent.effect-contracts.v0`, and graph effect payloads reference the selected
entry with `contractId` and canonical-to-source `contractArguments`.
Structured capability grants that cover known adapter operations carry the same
stable contract id plus the canonical `contractArgument`.
The registry also declares `risk` and `checkpoint` metadata. Read-only
contracts have no checkpoint trigger. Irreversible contracts declare
`requiredWhen: ["deny:uncheckpointed_irreversible_effect"]` with
`coverage: "source_order_after_effect"`, which the checker uses for
source-order checkpoint coverage.

Git commit effects use a named `message` constrained argument. The checker
binds `GitCommit(message: "...")` and `git.commit(message: "...")` to in-scope
`commit message: "..."` capability grants. Commit messages are normalized
before comparison; if no grant covers the normalized argument, the checker emits
`INTENT_CAPABILITY_DENIED`. The graph builder emits git commits as `Effect`
nodes with family `git`, action `commit`, and an `authorizes` edge from the
matching `Capability` node when covered.

Git push effects use a named `branch` or `remote` constrained argument. The
checker binds `git.push(branch: "...")` to in-scope `push branch: "..."`
capability grants and `git.push(remote: "...")` to in-scope
`push remote: "..."` capability grants. Simple branch and remote names are
normalized before comparison; if no grant covers the normalized argument, the
checker emits `INTENT_CAPABILITY_DENIED`.

Secret read effects are a Phase 2 static-model capability coverage check, not
secret-value handling. A capability declaration such as
`capability secret { read name: "DEPLOY_TOKEN" }` authorizes
`SecretRead(name: "DEPLOY_TOKEN")`. Secret read arguments are normalized by
name before comparison. A secret read outside the declared grants emits
`INTENT_CAPABILITY_DENIED`. The graph builder emits secret reads as `Effect`
nodes like other effects, with unknown trust because the static model does not
inspect or propagate secret values.

Ticket update effects use a named `id` constrained argument. A capability
declaration such as `capability ticket { update id: "CODE-123" }` authorizes
`TicketUpdate(id: "CODE-123")`. Ticket ids are normalized before comparison. A
ticket update outside the declared grants emits `INTENT_CAPABILITY_DENIED`. The
graph builder emits ticket updates as `Effect` nodes with family `ticket`,
action `update`, and an `authorizes` edge from the matching `Capability` node
when covered.

Deploy effects use a named `target` constrained argument. A capability
declaration such as `capability deploy { deploy target: "staging" }`
authorizes `Deploy(target: "staging")`. Deploy targets are normalized before
comparison. A deploy outside the declared grants emits
`INTENT_CAPABILITY_DENIED`. The graph builder emits deploys as `Effect` nodes
with family `deploy`, action `deploy`, and an `authorizes` edge from the
matching `Capability` node when covered.

## Lexical Rules

```ebnf
package_name    = package_part, { ".", package_part } ;
identifier_path = identifier, { ".", identifier } ;
package_part    = lowercase, { lowercase | digit | "_" } ;
identifier      = ( letter | "_" ), { letter | digit | "_" } ;
type_name       = uppercase, { letter | digit | "_" } ;

string          = '"', { string_char | escape }, '"' ;
escape          = "\\", ( '"' | "\\" | "n" | "r" | "t" ) ;
comment         = "#", { not_newline } ;
line_end        = { space | tab }, [ comment ], ( newline | eof ) ;
ws              = { space | tab | newline | comment } ;
spacing         = ws ;
s               = ( space | tab ), { space | tab } ;
```

Identifiers are ASCII only. Keywords are reserved and cannot be used as
identifiers in declaration positions:

```text
package goal context capability memory plan verify invariant step require deny
approval checkpoint timeout retry
```

Known built-in type names for checker binding are `String`, `Bool`, `Int`,
`Float`, `Record`, `List`, `Map`, `Goal`, `Context`, `Capability`, `Effect`,
`Step`, `Evidence`, `Assumption`, `Decision`, `Verified`, `Checkpoint`, and
`Provenance`.

String literals are double quoted only. Unterminated strings are syntax errors.
Single quoted strings are not accepted.

## Checker Binding Notes

The parser emits names and type reference strings; the checker owns binding.

- Duplicate type names in a file are `INTENT_NAME_DUPLICATE`.
- Duplicate goal names in a file are `INTENT_NAME_DUPLICATE`.
- Duplicate goal input names, step names, or step input names within their
  scope are `INTENT_NAME_DUPLICATE`.
- Type references that are neither built-ins nor file-local type declarations
  are `INTENT_TYPE_UNRESOLVED`.
- Step inputs that cannot bind to a goal input or earlier step output with the
  same normalized type are `INTENT_STEP_INPUT_UNRESOLVED`.
- Goal params become `input` graph nodes with goal scope.
- Step params become `input` graph nodes with step scope.
- Graph validation emits `INTENT_GRAPH_NODE_DUPLICATE` when two graph nodes
  share the same id because runtime edge resolution requires stable unique node
  ids.
- A bound step input creates a `data` edge from the matching goal input or
  earlier step output to that step input node.
- Context calls preserve source name, args, argKinds, argSpans, expression, and
  trust zone/source for checker and graph output.
- Repo context values are trusted local source values and are not
  capability-enforced yet.
- Structured `context web(...)` values are untrusted external source values.
  They use the first positional argument or a named `url` or `domain` argument,
  and bind to in-scope `web read domain: "..."` capability grants. URL hosts
  are compared against exact or wildcard granted domains; if no grant covers
  the host, the checker emits `INTENT_CONTEXT_UNDECLARED`.
- Structured `context documents(...)` values are trusted local source values.
  They use the first positional argument or a named `path` argument, and bind to
  in-scope `file read path: "..."` capability grants. Paths use the same
  normalization and matching rules as file read effects; if no grant covers the
  path, the checker emits `INTENT_CONTEXT_UNDECLARED`.
- Web/http read effects use the first positional argument or a named `url` or
  `domain` argument, and bind to in-scope `read domain: "..."` capability
  grants. URL hosts are compared against exact or wildcard granted domains; if
  no grant covers the host, the checker emits `INTENT_CAPABILITY_DENIED`.
- Git commit effects bind `GitCommit(message: "...")` and
  `git.commit(message: "...")` to in-scope
  `capability git { commit message: "..." }` grants. Commit messages are
  normalized before comparison; if no grant covers the normalized message, the
  checker emits `INTENT_CAPABILITY_DENIED`.
- Git push effects use a named `branch` or `remote` argument, and bind to
  in-scope `push branch: "..."` or `push remote: "..."` capability grants.
  Simple branch and remote names are normalized before comparison; if no grant
  covers the argument, the checker emits `INTENT_CAPABILITY_DENIED`.
- Secret read effects bind `SecretRead(name: "...")` to in-scope
  `capability secret { read name: "..." }` grants. Secret names are normalized
  before comparison; if no grant covers the normalized name, the checker emits
  `INTENT_CAPABILITY_DENIED`.
- Ticket update effects bind `TicketUpdate(id: "...")` to in-scope
  `capability ticket { update id: "..." }` grants. Ticket ids are normalized
  before comparison; if no grant covers the normalized id, the checker emits
  `INTENT_CAPABILITY_DENIED`.
- Deploy effects bind `Deploy(target: "...")` to in-scope
  `capability deploy { deploy target: "..." }` grants. Deploy targets are
  normalized before comparison; if no grant covers the normalized target, the
  checker emits `INTENT_CAPABILITY_DENIED`.
- Shell command, file write path, secret name, ticket id, deploy target, git
  push ref, and git commit message arguments must be literal or trusted before
  execution.
- Nonliteral constrained sink arguments that are not trusted are
  `INTENT_TRUST_FLOW_UNSAFE`.
- Capability blocks may contain `approval required`. Any effect authorized by
  that capability requires a step-local `approval ...` gate; missing approval is
  `INTENT_APPROVAL_MISSING`. Graph output records the policy on the
  `Capability` node and connects the step `Approval` node to each matching
  approval-required `Effect` node with an `approves` edge.
- Verify `shell("command")` and `shell(command: "command")` requirements bind
  to in-scope shell run capability grants. If no declared grant covers the
  normalized command, the checker emits `INTENT_VERIFY_UNDECLARED`.
- Context calls, effect calls, and verification shell calls carry `argSpans`
  alongside `args` and `argKinds`. `argSpans` maps argument keys such as `_0`,
  `path`, `command`, `url`, or `branch` to the source span of the argument token
  that should receive provenance and diagnostics.
- Goal-level `verify` requirements are pure assertions except for supported
  verification effects. Side-effect calls such as `FileWrite`, `GitPush`, web
  reads, git commits, deploys, or ticket updates inside `verify` emit
  `INTENT_VERIFY_IMPURE`.
- Enforce `deny production_deploy` by rejecting `Deploy` effects whose
  normalized `target` is `production` with `INTENT_INVARIANT_VIOLATION` at the
  invariant line span.
- Enforce `deny secret_write` by rejecting file write effects whose path or name
  looks like a secret, for example `.env`, `secret`, `token`, `credential`,
  `key`, or `password`, with `INTENT_INVARIANT_VIOLATION` at the invariant line
  span.
- Enforce `deny unrelated_file_write` by rejecting file write effects whose path
  is outside declared `repo(...)` context roots, with
  `INTENT_INVARIANT_VIOLATION` at the invariant line span.
- Step-body `require ...` lines become step requirement checks. They are
  emitted as graph `Check` nodes with `requires` edges into the owning step and
  `gates` edges to the owning goal, distinct from goal-level `verify`
  requirements.
- Step-body `approval ...` lines become step approval gates. They are emitted
  as graph `Approval` nodes, listed on the owning step node data, and connected
  by `approves` edges from each approval node to that step. Approval labels
  must be non-empty after trimming. Empty labels such as `approval ""` are
  `INTENT_APPROVAL_INVALID` at the approval line span and make graph output
  non-executable.
- Step-body `checkpoint ...` lines become graph `Checkpoint` nodes. They are
  listed on the owning step node data and connected by `checkpoints` edges from
  that step. Checkpoint labels must be non-empty after trimming. Empty labels
  such as `checkpoint ""` are `INTENT_CHECKPOINT_INVALID` at the checkpoint
  line span and make graph output non-executable.
- Step-body `timeout ...` and `retry ...` lines become graph `Policy` nodes.
  Timeout values must be simple positive durations such as `10s`, `5m`, `2h`,
  or `1d`; retry policies must be `max N` with a positive integer. Invalid
  policy syntax is `INTENT_POLICY_INVALID` at the policy line span. Valid
  policies are listed on the owning step node data and connected by `timeouts`
  or `retries` edges from each policy node to that step.
- Step summary arrays for inputs, effects, requirements, checkpoints,
  approvals, timeouts, retries, and memory accesses must exactly match owned
  child nodes or memory access edges in source order. Mismatches emit
  `INTENT_GRAPH_STEP_METADATA_INVALID`.
- Memory blocks must contain at least one parsed `retain ... until ...`
  retention rule. Missing retention is `INTENT_MEMORY_UNSCOPED`.
- Retention `until` values must be `goal_complete`, `goal.completed`, or a
  simple duration such as `30d`, `12h`, `45m`, or `10s`. Unsupported lifecycle
  targets are `INTENT_MEMORY_RETENTION_INVALID`.
- Parsed retention rules are emitted as checker data and graph `Memory` node
  `retentionRules` lifecycle data so runtimes can enforce retention without
  reparsing raw text.
- Emitted graph edges are validated so both endpoints resolve to nodes in the
  same payload, each step `Input` node has exactly one incoming `data` edge,
  every `Goal` node has its `${goal_id}:completion` `Completion` node and
  exactly one outgoing `completes` edge to that node with no `completes` edges
  to another completion,
  every `data` edge connects a goal `Input` node or step producer to a step
  `Input` consumer, every `Completion` node has exactly one incoming
  `completes` edge from a `Goal`, exactly one incoming `produces` edge from
  a `Step`, at least one incoming `verifies` edge from a `Check` node, and a
  `guards` edge count that matches the goal's `Invariant` nodes, and dependency
  and execution edge kinds are acyclic. An edge whose
  `from` or `to` endpoint is absent from the same graph payload emits
  `INTENT_GRAPH_EDGE_UNRESOLVED`; a step `Input` node without exactly one
  incoming `data` edge emits `INTENT_GRAPH_INPUT_UNBOUND`; a `data` edge with
  an invalid producer or consumer emits `INTENT_GRAPH_DATA_INVALID`; a `Goal`
  node whose parameters differ from owned goal input nodes or whose output
  metadata differs from its `Completion` emits
  `INTENT_GRAPH_GOAL_METADATA_INVALID`; a `Goal` node that lacks its
  `${goal_id}:completion` `Completion` node, lacks exactly one outgoing
  `completes` edge to that node, or has `completes` edges to another completion
  emits `INTENT_GRAPH_GOAL_COMPLETION_INVALID`; a
  `Effect` node or verification `Check` node with `data.effect` that lacks an
  incoming `authorizes` edge from a `Capability`, or whose incoming
  `authorizes` edge is not from a `Capability`, emits
  `INTENT_GRAPH_AUTHORIZATION_INVALID`; an `Effect` node that lacks exactly one
  incoming `requests` edge from its owning `Step`, or whose incoming `requests`
  edges are not from that owning `Step`, emits
  `INTENT_GRAPH_EFFECT_REQUEST_INVALID`; a `Step` node that lacks exactly one
  incoming `plans` edge from its owning `Goal`, or whose incoming `plans` edges
  are not from that owning `Goal`, emits `INTENT_GRAPH_STEP_PLAN_INVALID`; a
  `Step` node whose summary arrays differ from owned child nodes emits
  `INTENT_GRAPH_STEP_METADATA_INVALID`; a
  `Completion` node without the required incoming completion, verification, or
  guard coverage emits `INTENT_GRAPH_COMPLETION_INVALID`; cyclic graph edges emit
  `INTENT_GRAPH_CYCLE`; an `Invariant` node missing its `guards` edge to
  `Completion` or to any `Effect`, `Checkpoint`, or step-scoped `Check` node in
  the same goal emits `INTENT_GRAPH_GUARD_INVALID`; a goal with multiple
  `Step` nodes that does not have exactly one linear `precedes` chain across
  those steps, or whose `Step` producing `Completion` is not the tail step of
  that chain, emits `INTENT_GRAPH_STEP_SEQUENCE_INVALID`; a step-scoped `Check`
  without a `requires` edge to its owning `Step`, an `Approval` without an
  `approves` edge to its owning `Step` or to an approval-required `Effect` in
  that same step, a `Checkpoint` without a `checkpoints` edge from its owning
  `Step`, or a `Policy` without its `timeouts` or `retries` edge to its owning
  `Step` emits `INTENT_GRAPH_STEP_ATTACHMENT_INVALID`; two graph nodes with the
  same id emit `INTENT_GRAPH_NODE_DUPLICATE` because runtime edge resolution
  requires stable unique node ids; a graph node kind that is not one of the
  runtime-supported Intent graph node kinds emits
  `INTENT_GRAPH_NODE_KIND_INVALID`; an edge kind that is not one of the
  runtime-supported Intent graph relationship kinds emits
  `INTENT_GRAPH_EDGE_KIND_INVALID`.
- Graph nodes and edges record trust metadata where it helps downstream
  runtimes explain allowed or rejected flows.
- Each step input node creates a `requires` edge to its owning step.
- Every goal emits one `completion` graph node.
- Required `verify` checks create `verifies` edges to the completion node,
  applicable `invariant` rules create `guards` edges to completion and every
  effect, checkpoint, and step requirement check in the same goal, and the last
  step in source order creates a `produces` edge.
- Completion node data records whether citation provenance is required and the
  final-step memory citations that satisfy it.
- Completion node data records whether final-state checkpointing is required
  and the final-step checkpoints that satisfy it.

## Whitespace And Comments

Whitespace is insignificant except where it separates tokens. Newlines terminate
single-line declarations and statements. Comments begin with `#` outside strings
and continue to the end of the line. A trailing comment is not part of the
preceding raw expression.

```intent
package examples.checkout # package comment

goal "ship checkout fix" {
  context repo("./")

  verify {
    require shell("npm test").exit_code == 0 # check comment
  }
}
```

## Source Spans

Every AST node must carry a source span:

- `start_byte` inclusive.
- `end_byte` exclusive.
- `start_line` and `start_column`, both 1-based.
- `end_line` and `end_column`, both 1-based.

Spans must cover the full syntactic node, including keywords and delimiters.
Token spans must cover only the token text. Raw expression spans must exclude the
leading `require` or `deny` keyword and include the expression text before the
terminating newline.

Goal header params and step header params must carry a source `span` on the
parameter object itself. The parameter span covers the parameter name, type
separator, and type reference, excluding surrounding delimiters and unrelated
whitespace.

Comments and whitespace do not become AST nodes, but diagnostics must be able to
reference their byte locations when they cause lexical errors.
