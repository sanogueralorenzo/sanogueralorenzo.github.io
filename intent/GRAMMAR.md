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
- Step declarations inside `plan`, including step-local requirements and
  checkpoints.
- `require` and `deny` statements.
- Effect call arguments in simple call expressions.
- Line comments.
- String literals.
- Identifiers.

The parser must reject unsupported top-level declarations instead of treating
them as opaque text.

## File Shape

```ebnf
file           = spacing, package_decl, spacing, { top_level_decl, spacing },
                 eof ;
top_level_decl = type_decl | goal_decl ;
package_decl   = "package", s, package_name, line_end ;

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
declarations. More than one type or goal may appear in a file.

Type declarations are line-based in the first prototype. The optional
definition is preserved as raw text and is not parsed into record fields,
aliases, enum cases, or generic parameters yet.

Goal signature params are goal inputs. The parser preserves their source order,
names, types, and spans so the checker can emit graph input nodes and data
dependency edges.

## Goal Blocks

```ebnf
context_block    = "context", s, call_expr, line_end ;
capability_block = "capability", s, identifier, ws, block ;
memory_block     = "memory", s, identifier, ws, "{", ws,
                   { memory_stmt, ws }, "}" ;
memory_stmt      = retain_stmt | raw_memory_stmt ;
retain_stmt      = "retain", s, retain_subject, s, "until", s,
                   retain_until, line_end ;
retain_subject   = raw_text_until_until_keyword ;
retain_until     = raw_text_until_terminator ;
raw_memory_stmt  = raw_text_until_terminator, line_end ;
plan_block       = "plan", ws, "{", ws, { step_decl, ws }, "}" ;
verify_block     = "verify", ws, "{", ws, { require_stmt, ws }, "}" ;
invariant_block  = "invariant", ws, "{", ws, { deny_stmt, ws }, "}" ;

require_stmt     = "require", s, raw_expr, line_end ;
deny_stmt        = "deny", s, raw_expr, line_end ;
```

`context` is a single-line declaration in this milestone. Context declarations
that describe web resources or browser/page state are treated as untrusted by
the checker unless a later policy explicitly upgrades them. `capability` bodies
are parsed as statement lists whose items are preserved as raw spanned lines.
`memory` bodies are parsed as statement lists, and every `retain ... until ...`
line is additionally parsed into structured `retentionRules` data with a
retained subject span and an until-condition span. `verify` accepts only
`require`; `invariant` accepts only `deny`.

Every `memory` block must include at least one `retain ... until ...` retention
rule. A memory block without a parsed retention rule is syntactically valid, but
the checker emits `INTENT_MEMORY_UNSCOPED` because the retained state has no
declared lifecycle.

## Steps

```ebnf
step_decl  = "step", s, identifier, [ params ], ws, "->", ws, type_ref,
             ( line_end | ws, step_body ) ;
step_body  = "{", ws, { step_item, ws }, "}" ;
step_item  = step_require_stmt | step_checkpoint_stmt ;
step_require_stmt = "require", s, raw_expr, line_end ;
step_checkpoint_stmt = "checkpoint", s, raw_expr, line_end ;
params     = "(", ws, [ param, { ws, ",", ws, param } ], ws, ")" ;
param      = identifier, ws, ":", ws, type_ref ;
type_ref   = identifier, { ws, type_suffix } ;
type_suffix = "<", ws, type_ref, { ws, ",", ws, type_ref }, ws, ">" ;
```

Step declarations may be signatures only or may include a body containing
step-local `require ...` and `checkpoint ...` lines. Effect bodies, retries,
timeouts, and execution statements are out of scope. Step input names are local
to the step signature; the checker binds inputs by matching their type against
goal inputs and previous step outputs in source order. Each step param becomes
a step input port in the checked graph.

`require ...` lines inside a step body are parsed as step requirements. They are
not goal-level `verify` checks and do not create completion verification gates.
The graph builder emits each step requirement as a `Check` node, creates a
`requires` edge from that `Check` node into the owning `Step`, and creates a
`gates` edge from that `Check` node to the owning `Goal`.

`checkpoint ...` lines inside a step body are parsed as step checkpoint
statements. They are not memory retention declarations and do not become
goal-level verification checks. The graph builder emits each step checkpoint as
a `Checkpoint` node, lists it on the owning step node data, and creates a
`checkpoints` edge from the owning `Step` to that `Checkpoint`.

## Expressions

The parser preserves raw expression text for later phases, but it also parses
simple call expressions used for contexts, effects, and checks. This lets the
checker inspect effect arguments without evaluating the full expression
language.

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
names, literal values, and nested call values.

Unsupported argument syntax inside a parsed call is `INTENT_PARSE_ERROR`.
Unsupported expression syntax outside the call envelope remains raw text unless
the surrounding grammar requires a call expression.

Examples of parseable effect calls:

```intent
file.read(path: "intent/GRAMMAR.md")
file.write("intent/STATIC_MODEL.md")
shell.exec(command: "npm test")
web.read(url: "https://docs.example.com/guide")
http.get("https://api.example.com/status")
git.push(branch: "main")
git.push(remote: "origin")
```

Inside `verify` requirements, `shell("npm test")` and
`shell(command: "npm test")` are parseable verification shell calls. The checker
binds them to declared shell run capability grants instead of treating them as
opaque predicate text.

Shell command arguments are trust-sensitive in the first checker prototype. A
shell command argument must be either a string literal or a value already marked
trusted by the checker. Nonliteral shell command expressions that are not
trusted produce `INTENT_TRUST_FLOW_UNSAFE` rather than being treated as an
opaque command string.

Git push effects use a named `branch` or `remote` constrained argument. The
checker binds `git.push(branch: "...")` to in-scope `push branch: "..."`
capability grants and `git.push(remote: "...")` to in-scope
`push remote: "..."` capability grants. Simple branch and remote names are
normalized before comparison; if no grant covers the normalized argument, the
checker emits `INTENT_CAPABILITY_DENIED`.

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
checkpoint
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
- A bound step input creates a `data` edge from the matching goal input or
  earlier step output to that step input node.
- Web context values are untrusted source values.
- Web/http read effects use the first positional argument or a named `url` or
  `domain` argument, and bind to in-scope `read domain: "..."` capability
  grants. URL hosts are compared against exact or wildcard granted domains; if
  no grant covers the host, the checker emits `INTENT_CAPABILITY_DENIED`.
- Git push effects use a named `branch` or `remote` argument, and bind to
  in-scope `push branch: "..."` or `push remote: "..."` capability grants.
  Simple branch and remote names are normalized before comparison; if no grant
  covers the argument, the checker emits `INTENT_CAPABILITY_DENIED`.
- Shell command arguments must be literal or trusted before execution.
- Nonliteral shell command arguments that are not trusted are
  `INTENT_TRUST_FLOW_UNSAFE`.
- Verify `shell("command")` and `shell(command: "command")` requirements bind
  to in-scope shell run capability grants. If no declared grant covers the
  normalized command, the checker emits `INTENT_VERIFY_UNDECLARED`.
- Step-body `require ...` lines become step requirement checks. They are
  emitted as graph `Check` nodes with `requires` edges into the owning step and
  `gates` edges to the owning goal, distinct from goal-level `verify`
  requirements.
- Step-body `checkpoint ...` lines become graph `Checkpoint` nodes. They are
  listed on the owning step node data and connected by `checkpoints` edges from
  that step.
- Memory blocks must contain at least one parsed `retain ... until ...`
  retention rule. Missing retention is `INTENT_MEMORY_UNSCOPED`.
- Parsed retention rules are emitted as checker data and graph `Memory` node
  `retentionRules` lifecycle data so runtimes can enforce retention without
  reparsing raw text.
- Graph nodes and edges record trust metadata where it helps downstream
  runtimes explain allowed or rejected flows.
- Each step input node creates a `requires` edge to its owning step.
- Every goal emits one `completion` graph node.
- Required `verify` checks create `verifies` edges to the completion node,
  applicable `invariant` rules create `guards` edges, and the last step in
  source order creates a `produces` edge.

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

Comments and whitespace do not become AST nodes, but diagnostics must be able to
reference their byte locations when they cause lexical errors.
