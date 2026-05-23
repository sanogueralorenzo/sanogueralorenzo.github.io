# Jury Examples

These examples show how Jury can judge standalone agent claims.

## Runnable Adoption Fixture

[code-change-adoption](code-change-adoption) is the end-to-end local fixture for a code-change review. It runs `init`, `claim create`, `evidence add`, `critic run`, `judge`, `gate`, and `bundle export`, then preserves the retry verdict, failing gate output, and portable review bundle as checked-in artifacts.

## Code Change Gate

Claim: "The checkout fix is ready to merge."

Required evidence:

- Diff is limited to checkout files.
- Regression test covers the reported failure.
- Test command passes.

Possible objection:

```json
{
  "id": "obj_missing_regression_test",
  "summary": "The change fixes the implementation but does not prove the reported failure cannot return.",
  "raised_by": "critic:test",
  "severity": "high",
  "status": "open",
  "evidence_ids": ["ev_diff_checkout"]
}
```

Failure modes:

- Passing tests with missing coverage.
- Risky auth or storage changes hidden inside a large diff.
- Reviewer objections marked resolved without new evidence.

Retry verdict:

```json
{
  "schema_version": "jury.verdict.v1",
  "claim_id": "claim_checkout_ready",
  "decision": "retry",
  "reason": "The fix needs a regression test before it can be accepted.",
  "evidence_ids": ["ev_diff_checkout", "ev_npm_test"],
  "objection_ids": ["obj_missing_regression_test"],
  "waiver_ids": [],
  "decided_by": "judge:local",
  "decided_at": "2026-05-23T00:00:00Z"
}
```

## Research Report Gate

Claim: "The model comparison report is accurate enough to send."

Required evidence:

- Every factual claim has a citation.
- Sources are current enough for the report date.
- Pricing and limits are copied from primary sources.

Possible objection:

```json
{
  "id": "obj_uncited_pricing_claim",
  "summary": "The report includes a pricing claim without a source.",
  "raised_by": "critic:citation",
  "severity": "high",
  "status": "open",
  "evidence_ids": ["ev_report_scan"]
}
```

Failure modes:

- Hallucinated citations.
- Outdated sources.
- Unsupported conclusions.
- Confidence language stronger than the evidence.

Reject verdict:

```json
{
  "schema_version": "jury.verdict.v1",
  "claim_id": "claim_report_ready",
  "decision": "reject",
  "reason": "The report contains uncited pricing claims, so the accuracy claim is not supported.",
  "evidence_ids": ["ev_report_scan"],
  "objection_ids": ["obj_uncited_pricing_claim"],
  "waiver_ids": [],
  "decided_by": "judge:local",
  "decided_at": "2026-05-23T00:00:00Z"
}
```

## Deployment Gate

Claim: "The billing service can be deployed."

Required evidence:

- Smoke tests pass.
- Rollback plan exists.
- On-call approval is recorded for production impact.

Possible objection:

```json
{
  "id": "obj_missing_rollback",
  "summary": "The deployment has no rollback evidence.",
  "raised_by": "policy:release",
  "severity": "critical",
  "status": "open",
  "evidence_ids": []
}
```

Failure modes:

- Staging passes but production config differs.
- Rollback steps are missing or untested.
- Approval is stale or from the wrong owner.
- Incident freeze rules are ignored.

Human-decision verdict:

```json
{
  "schema_version": "jury.verdict.v1",
  "claim_id": "claim_billing_deploy",
  "decision": "human_decision",
  "reason": "Production deployment risk requires explicit on-call approval.",
  "evidence_ids": ["ev_smoke_tests"],
  "objection_ids": ["obj_missing_rollback"],
  "waiver_ids": [],
  "decided_by": "judge:local",
  "decided_at": "2026-05-23T00:00:00Z"
}
```

## Tool-Use Gate

Claim: "The agent may call the external email tool."

Required evidence:

- Purpose is declared.
- Scope is limited to required messages.
- Sensitive fields are redacted or excluded.
- User approval exists when needed.

Possible objection:

```json
{
  "id": "obj_scope_too_broad",
  "summary": "The requested email scope includes all inbox messages instead of the task-specific thread.",
  "raised_by": "policy:privacy",
  "severity": "critical",
  "status": "open",
  "evidence_ids": ["ev_tool_request"]
}
```

Failure modes:

- Wrong account, tenant, repo, or message thread.
- Irreversible side effects.
- Hidden network calls.
- Tool arguments inferred instead of explicitly provided.

Reject verdict:

```json
{
  "schema_version": "jury.verdict.v1",
  "claim_id": "claim_email_tool_use",
  "decision": "reject",
  "reason": "The tool request is broader than the stated task requires.",
  "evidence_ids": ["ev_tool_request"],
  "objection_ids": ["obj_scope_too_broad"],
  "waiver_ids": [],
  "decided_by": "judge:local",
  "decided_at": "2026-05-23T00:00:00Z"
}
```
