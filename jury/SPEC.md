# Jury Spec

This document defines the first standalone contract for Jury.

Jury starts from one rule: an important agent outcome is not true just because an agent says it is true. The outcome is a claim. The claim needs evidence, review, objections, and a verdict.

## Core Objects

### Claim

A claim is the thing being judged.

Required fields:

- `id`: stable identifier for the claim.
- `version`: integer version of the claim text and scope.
- `summary`: short human-readable statement.
- `claimant`: actor making the claim.
- `scope`: files, systems, documents, commands, or external resources covered by the claim.
- `impact`: `low`, `medium`, `high`, or `critical`.
- `status`: current lifecycle state.
- `created_at`: timestamp for audit ordering.

Examples:

- "The checkout fix is ready to merge."
- "The incident report is accurate enough to send."
- "The billing service can be deployed."
- "The agent may call this external tool."

### Evidence

Evidence is support for or against a claim.

Required fields:

- `id`: stable identifier.
- `type`: `command`, `diff`, `artifact`, `citation`, `screenshot`, `log`, `review`, or `manual`.
- `summary`: what this evidence shows.
- `source`: where the evidence came from.
- `status`: `pending`, `passed`, `failed`, or `inconclusive`.
- `collected_at`: timestamp for audit ordering.

Evidence should be reproducible when possible. If it cannot be reproduced, the verdict must say why the evidence is still acceptable.

### Check

A check is a required review, verification, policy, or approval condition.

Required fields:

- `id`: stable identifier.
- `type`: `critic`, `verifier`, `policy`, or `human_approval`.
- `required`: whether this check must complete before judgment.
- `status`: `pending`, `passed`, `failed`, `waived`, or `not_applicable`.
- `assigned_to`: actor or tool responsible for the check.
- `evidence_ids`: evidence generated or consumed by the check.

Checks answer a different question than objections. A check says what must be evaluated. An objection says what challenge was raised during evaluation.

### Objection

An objection is a structured challenge to a claim.

Required fields:

- `id`: stable identifier.
- `summary`: short challenge statement.
- `raised_by`: reviewer, tool, policy, or human source.
- `severity`: `low`, `medium`, `high`, or `critical`.
- `status`: `open`, `resolved`, `waived`, or `rejected`.
- `evidence_ids`: evidence attached to the objection.
- `resolution`: required when the status is not `open`.

An objection should be specific enough to resolve. "This seems risky" is not enough. "No rollback evidence exists for a production deploy" is enough.

### Waiver

A waiver records an explicit decision to accept a known unresolved risk.

Required fields:

- `id`: stable identifier.
- `objection_id`: objection being waived.
- `approved_by`: actor accepting the risk.
- `reason`: why the risk is acceptable.
- `expires_at`: optional timestamp for temporary waivers.

Waivers are not hidden approvals. They are part of the verdict.

### Verdict

A verdict is the final decision record for a claim.

Required fields:

- `schema_version`: `jury.verdict.v1`.
- `claim_id`: claim being judged.
- `decision`: `accept`, `reject`, `retry`, or `human_decision`.
- `reason`: concise explanation for the decision.
- `evidence_ids`: evidence considered by the judge.
- `objection_ids`: objections considered by the judge.
- `waiver_ids`: waivers accepted by the judge.
- `decided_by`: actor producing the verdict.
- `decided_at`: timestamp for audit ordering.

## Lifecycle

1. `draft`: a claim is created but not ready for review.
2. `submitted`: the claimant says the claim is ready to judge.
3. `screening`: Jury determines the required checks.
4. `in_review`: critics, verifiers, and policies collect evidence and objections.
5. `revision_required`: the claimant must answer objections, add evidence, or request waivers.
6. `ready_for_judgment`: required checks are complete.
7. `decided`: the judge emits a verdict.
8. `archived`: the verdict is retained for audit and future review.

Claims can move from `revision_required` back to `in_review` when a fix changes the evidence. Claims should not move from `decided` back to `in_review`; create a new claim version if the underlying work changes.

## Verdict Rules

- `accept`: all required evidence passed, no open high-impact objection remains, and every waiver is explicit.
- `reject`: the claim is false, unsafe, out of scope, or missing essential evidence.
- `retry`: the claim may become acceptable after specific fixes or missing checks.
- `human_decision`: the system found a judgment call it should not resolve alone.

## Invariants

1. A verdict must reference exactly one claim.
2. A high or critical objection cannot disappear; it must be resolved, waived, or rejected with a reason.
3. A waiver must name the objection it accepts.
4. A command evidence item must include the command and exit code.
5. A verdict cannot be `accept` when required evidence is `failed`.
6. A verdict cannot be `accept` when a critical objection is still open.
7. Every decision must have a reason.
8. A required check must end in `passed`, `failed`, `waived`, or `not_applicable`.
9. A verdict must reference the claim version it judged.
10. Decided verdicts are append-only.

## Minimal Verdict JSON

```json
{
  "schema_version": "jury.verdict.v1",
  "claim_id": "claim_checkout_ready",
  "claim_version": 1,
  "decision": "retry",
  "reason": "The implementation may be correct, but the failed coupon path has no regression test yet.",
  "evidence_ids": ["ev_npm_test"],
  "objection_ids": ["obj_missing_coupon_regression"],
  "waiver_ids": [],
  "decided_by": "judge:local",
  "decided_at": "2026-05-23T00:00:00Z"
}
```

## Non-Goals

- Jury does not replace tests, linters, reviewers, or policy engines.
- Jury does not decide what work should be done.
- Jury does not require all reviewers to be AI agents.
- Jury does not hide uncertainty behind a single confidence score.
