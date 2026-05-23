# Jury Roadmap

Jury should grow from a written review model into a small local CLI that can judge real agent claims.

## Phase 1: Written Contract

Goal: make the review model precise enough to implement.

Deliverables:

- `README.md` explains the standalone project goal.
- `SPEC.md` defines claims, evidence, objections, waivers, verdicts, lifecycle, and invariants.
- `examples/README.md` shows realistic review gates.

Acceptance checks:

- A reader can describe what a verdict contains.
- A reader can tell the difference between `reject`, `retry`, and `human_decision`.
- The examples do not depend on any external agent runtime.

## Phase 2: Local Data Model

Goal: represent Jury records as deterministic JSON.

Deliverables:

- JSON schema files for claims, evidence, objections, waivers, and verdicts.
- Example fixtures for accepted, rejected, retried, and human-decision verdicts.
- A validation command that rejects malformed records with exact field errors.

Acceptance checks:

- Valid fixtures pass.
- Invalid fixtures fail with stable non-zero exit codes.
- Required evidence and unresolved critical objections are enforced.

## Phase 3: Prototype CLI

Goal: make Jury usable from a terminal.

Proposed commands:

```shell
jury init
jury claim create --summary "checkout fix is ready" --impact high
jury claim transition --claim claim_checkout_ready --status screening
jury claim transition --claim claim_checkout_ready --status in_review
jury status --claim claim_checkout_ready
jury check add --claim claim_checkout_ready --type verifier --summary "test command must pass"
jury evidence add --claim claim_checkout_ready --type command --command "npm test" --exit-code 0
jury critic run --claim claim_checkout_ready --role tests
jury critic run --claim claim_checkout_ready --role security
jury critic run --claim claim_checkout_ready --role scope --changed-files src/checkout/applyCoupon.ts
jury check update --id check_claim_checkout_ready_verifier_test_command_must_pass --status passed --resolution "npm test passed"
jury objection add --claim claim_checkout_ready --severity high --summary "missing regression test"
jury objection resolve --id obj_missing_regression_test --resolution "added test"
jury judge --claim claim_checkout_ready --format json
jury check --strict
jury gate --claim claim_checkout_ready --verdict verdict.json
```

Acceptance checks:

- Commands are non-interactive and repeatable.
- The CLI preserves deterministic output ordering.
- `jury judge` emits `jury.verdict.v1`.
- `jury check --strict` can run in CI.
- Claim, evidence, objection, waiver, and verdict writes are append-only unless a command explicitly creates a new version.

## Phase 4: Deterministic Critics

Goal: raise useful objections without requiring model-based reviewers.

Deliverables:

- `tests` critic for missing, failed, or weak validation.
- `security` critic for secrets, broad permissions, unsafe commands, and risky external calls.
- `scope` critic for unrelated file changes or vague claims.

Acceptance checks:

- Critics emit structured objections.
- Medium and high unresolved objections prevent `accept`.
- Low objections can allow `accept` only with judge explanation.

## Phase 5: Review Gates

Goal: block risky actions unless Jury emits an acceptable verdict.

Deliverables:

- A merge gate that requires an `accept` verdict for high-impact code claims.
- A deploy gate that requires rollback evidence and human approval where configured.
- A tool-use gate that rejects claims with missing scope, purpose, or risk evidence.

Acceptance checks:

- Gates fail closed when required verdict files are missing.
- Gates explain the exact missing field or unresolved objection.
- Gates do not require network access.

## Phase 6: Review Quality

Goal: make objections useful instead of noisy.

Deliverables:

- Objection quality checks for vague, duplicate, or unactionable objections.
- Severity calibration rules.
- Review summaries that separate blockers from low-risk notes.

Acceptance checks:

- Duplicate objections collapse into one review thread.
- Low-severity objections cannot block a critical verdict unless policy says so.
- A retry verdict includes specific next actions.

## First Prototype Slice

The first implementation should support one local repository and one claim type: "this code change is ready."

Minimum useful flow:

1. Create a claim.
2. Attach command evidence.
3. Add or resolve objections.
4. Emit a verdict.
5. Validate the verdict in CI.

Demo target:

```shell
jury demo code-change
```

The demo should create a sample claim, run verification, raise one objection, resolve it, and emit `verdict.json`.
