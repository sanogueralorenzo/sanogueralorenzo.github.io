# Intent Fixtures

These fixtures exercise the Phase 2 static model parser and checker.

## Valid

- `valid_code_change.intent`: code-change goal with repository context, declared file and shell capabilities, plan steps, verification, and invariants.
- `valid_research.intent`: research goal with web and local document context, read-only capabilities, plan steps, citation verification, and invariants.

## Invalid

- `invalid_missing_verification.intent`: declares mutating effects but omits the required verification gate.
- `invalid_undeclared_effect.intent`: uses a git push step without declaring the matching capability.
