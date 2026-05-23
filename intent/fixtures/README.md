# Intent Fixtures

These fixtures exercise the Phase 2 static model parser and checker.

## Valid

- `valid_code_change.intent`: code-change goal with declared step output types, repository context, file and shell capabilities, plan steps, verification, and invariants.
- `valid_research.intent`: research goal with declared source, claim, and report types, web and local document context, read-only capabilities, plan steps, citation verification, and invariants.

## Invalid

- `invalid_missing_verification.intent`: declares mutating effects but omits the required verification gate.
- `invalid_undeclared_effect.intent`: uses a git push step without declaring the matching capability.
- `invalid_unresolved_type.intent`: uses a step output type that is not declared.
- `invalid_unresolved_step_input.intent`: uses a declared step input type before any goal input or earlier step produces it.
- `invalid_duplicate_step_name.intent`: declares the same step name twice in one plan.
