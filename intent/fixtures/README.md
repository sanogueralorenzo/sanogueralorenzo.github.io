# Intent Fixtures

These fixtures exercise the Phase 2 static model parser and checker.

## Valid

- `valid_code_change.intent`: code-change goal with declared step output types, repository context, file and shell capabilities, allowed `FileWrite` and `ShellExec` calls, verification, and invariants.
- `valid_dependency_graph.intent`: named goal input feeding the first step, followed by prior step outputs feeding later steps for graph dependency coverage.
- `valid_research.intent`: research goal with declared source, claim, and report types, web and local document context, read-only capabilities, plan steps, citation verification, and invariants.
- `valid_trust_flow_shell_literal.intent`: trust-flow goal where `ShellExec` uses a literal command declared by shell capability.

## Invalid

- `invalid_missing_verification.intent`: declares mutating effects but omits the required verification gate.
- `invalid_undeclared_effect.intent`: uses a git push step without declaring the matching capability.
- `invalid_file_write_outside_capability.intent`: calls `FileWrite` for a path outside the declared write grant.
- `invalid_shell_exec_outside_capability.intent`: calls `ShellExec` with a command outside the declared shell grant.
- `invalid_verify_shell_without_capability.intent`: requires `shell("npm run lint")` in verification without declaring the matching shell run grant.
- `invalid_memory_without_retention.intent`: declares a memory block without any `retain ... until ...` retention rule.
- `invalid_unresolved_type.intent`: uses a step output type that is not declared.
- `invalid_unresolved_step_input.intent`: uses a declared step input type before any goal input or earlier step produces it.
- `invalid_duplicate_step_name.intent`: declares the same step name twice in one plan.
- `invalid_trust_flow_untrusted_shell_input.intent`: feeds a value produced from web context into `ShellExec(command: input)`.
