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
- Step declarations inside `plan`.
- `require` and `deny` statements.
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

## Goal Blocks

```ebnf
context_block    = "context", s, call_expr, line_end ;
capability_block = "capability", s, identifier, ws, block ;
memory_block     = "memory", s, identifier, ws, block ;
plan_block       = "plan", ws, "{", ws, { step_decl, ws }, "}" ;
verify_block     = "verify", ws, "{", ws, { require_stmt, ws }, "}" ;
invariant_block  = "invariant", ws, "{", ws, { deny_stmt, ws }, "}" ;

require_stmt     = "require", s, raw_expr, line_end ;
deny_stmt        = "deny", s, raw_expr, line_end ;
```

`context` is a single-line declaration in this milestone. `capability` and
`memory` bodies are parsed as statement lists whose items are preserved as raw
spanned lines. `verify` accepts only `require`; `invariant` accepts only `deny`.

## Steps

```ebnf
step_decl  = "step", s, identifier, [ params ], ws, "->", ws, type_ref,
             line_end ;
params     = "(", ws, [ param, { ws, ",", ws, param } ], ws, ")" ;
param      = identifier, ws, ":", ws, type_ref ;
type_ref   = identifier, { ws, type_suffix } ;
type_suffix = "<", ws, type_ref, { ws, ",", ws, type_ref }, ws, ">" ;
```

Step declarations are signatures only for the first milestone. Step bodies,
effect bodies, retries, timeouts, and execution statements are out of scope.
Step input names are local to the step signature; the checker binds inputs by
matching their type against goal inputs and previous step outputs in source
order.

## Expressions

The parser only tokenizes expression starts and preserves raw expression text for
later phases.

```ebnf
call_expr = identifier_path, ws, "(", raw_until_matching_paren, ")" ;
raw_expr  = raw_text_until_terminator ;
raw_type_def = raw_text_until_terminator ;
```

Raw expressions must still preserve source spans and balanced string/comment
handling, so diagnostics can point at the original text.

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
