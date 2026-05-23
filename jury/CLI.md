# Jury CLI Reference

Jury is a dependency-free local CLI:

```shell
node jury/bin/jury.mjs <command> [flags]
```

Use `--state-dir <path>` to keep review state outside the default `.jury/` directory. Use `--json` for machine-readable output.

## Core Flow

```shell
node jury/bin/jury.mjs init
node jury/bin/jury.mjs claim create --id claim_ready --summary "change is ready" --scope jury --impact high
node jury/bin/jury.mjs claim transition --claim claim_ready --status screening
node jury/bin/jury.mjs claim transition --claim claim_ready --status in_review
node jury/bin/jury.mjs check add --id check_tests --claim claim_ready --type verifier --summary "tests must pass"
node jury/bin/jury.mjs evidence add --claim claim_ready --type command --run "node --test jury/test/*.test.mjs"
node jury/bin/jury.mjs critic run --claim claim_ready --role tests
node jury/bin/jury.mjs critic run --claim claim_ready --role security
node jury/bin/jury.mjs critic run --claim claim_ready --role scope --changed-files jury/bin/jury.mjs,jury/test/jury.test.mjs
node jury/bin/jury.mjs check update --id check_tests --status passed --resolution "tests passed"
node jury/bin/jury.mjs judge --claim claim_ready --out verdict.json
node jury/bin/jury.mjs gate --claim claim_ready --verdict verdict.json
node jury/bin/jury.mjs check --strict
```

## Commands

- `init`: creates append-only JSONL state files.
- `claim create`: creates a submitted claim.
- `claim transition`: moves a claim through the allowed lifecycle.
- `check add`: creates a durable review condition.
- `check update`: appends a new check state.
- `evidence add`: records command, file, citation, manual, policy, or tool evidence.
- `critic run`: runs deterministic `tests`, `security`, or `scope` critics.
- `objection add`: records a manual objection.
- `objection resolve`: appends a resolved objection state.
- `waiver add`: records explicit risk acceptance for an objection.
- `status`: prints the current claim review bundle.
- `judge`: emits and records a verdict.
- `gate`: exits zero only for an `accept` verdict that matches current claim state.
- `check --strict`: validates JSONL files, schema files, and cross-record consistency.
- `demo code-change`: creates a sample accepted code-change verdict.

## Diagnostics

`gate --claim <id>` reports `missing_fields`, `unresolved_objections`, `next_actions`, and `consistency_errors` when the verdict does not match current state.

`check --strict` reports malformed JSON, schema problems, missing claim references, missing evidence/check/objection/waiver references, cross-claim references, and verdict claim-version mismatches.
