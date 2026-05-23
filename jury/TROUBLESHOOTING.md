# Jury CI Troubleshooting

Use this guide when a Jury CI gate emits a non-accept verdict.

## Inspect Artifacts

Start with `gate.json`. It is the small CI result that tells the job whether to proceed:

- `ok`: `true` only when the verdict is accepted.
- `decision`: `accept`, `reject`, `retry`, or `human_decision`.
- `reason`: the judge's short explanation.
- `missing_fields`: required claim or evidence fields missing from current state.
- `unresolved_objections`: blocking objections that still need resolution.
- `next_actions`: concrete follow-up work for retry or human-decision verdicts.

Then inspect `review-bundle.json`. It is the portable state snapshot for the claim:

- `claim_id`: the claim under review.
- `producer`: the tool name, version, and command that produced the bundle.
- `provenance`: the source, revision, workflow, and run id attached at export time.
- `attestation`: optional `hmac-sha256` or `rsa-sha256` signature metadata for verifying the bundle payload.
- `records.claims`: claim versions and lifecycle transitions.
- `records.checks`: required checks and their current status.
- `records.evidence`: command, citation, manual, or tool-call evidence.
- `records.objections`: reviewer objections still attached to the claim.
- `records.verdicts`: verdict history exported with the bundle.

```shell
node -e "const gate=JSON.parse(require('node:fs').readFileSync('gate.json','utf8')); console.log(JSON.stringify({ok:gate.ok,decision:gate.decision,reason:gate.reason,missing_fields:gate.missing_fields,unresolved_objections:gate.unresolved_objections,next_actions:gate.next_actions},null,2))"
node -e "const bundle=JSON.parse(require('node:fs').readFileSync('review-bundle.json','utf8')); console.log(JSON.stringify({claim_id:bundle.claim_id,producer:bundle.producer,provenance:bundle.provenance,claims:bundle.records.claims.length,checks:bundle.records.checks.length,evidence:bundle.records.evidence.length,objections:bundle.records.objections.length,verdicts:bundle.records.verdicts.length},null,2))"
node jury/bin/jury.mjs bundle preflight --bundle review-bundle.json --expect-producer-name @sanogueralorenzo/jury --expect-producer-version 0.1.0 --expect-source local --expect-revision-pattern "^unknown$"
node jury/bin/jury.mjs bundle preflight --bundle review-bundle.json --require-attestation true --verify-attestation-key "$JURY_BUNDLE_ATTEST_KEY"
node jury/bin/jury.mjs bundle preflight --bundle review-bundle.json --require-attestation true --verify-attestation-public-key ci-public.pem
```

## Common Causes

- `reject`: command evidence failed, such as a test or smoke command with a non-zero exit code.
- `retry`: required evidence is missing, a required check is pending, a claim has no explicit scope, or a blocking objection is unresolved.
- `human_decision`: the claim needs explicit approval before the system should proceed.
- stale verdict: the claim changed after `verdict.json` was written, so the verdict no longer matches current claim state.

## Retry Example

This example produces a retry verdict because the claim has no command evidence and the deterministic tests critic opens a blocking objection.

```shell
node jury/bin/jury.mjs init --state-dir .jury-retry
node jury/bin/jury.mjs claim create --state-dir .jury-retry --id claim_retry_missing_evidence --summary "change is ready"
node jury/bin/jury.mjs critic run --state-dir .jury-retry --claim claim_retry_missing_evidence --role tests
node jury/bin/jury.mjs judge --state-dir .jury-retry --claim claim_retry_missing_evidence --out verdict.retry.json
if node jury/bin/jury.mjs gate --state-dir .jury-retry --claim claim_retry_missing_evidence --verdict verdict.retry.json --json > gate.retry.json; then exit 1; else test $? -eq 1; fi
node jury/bin/jury.mjs bundle export --state-dir .jury-retry --claim claim_retry_missing_evidence --out review-bundle.retry.json
node jury/bin/jury.mjs check --state-dir .jury-retry --strict
```

Inspect `gate.retry.json` for `missing_fields`, `unresolved_objections`, and `next_actions`. Inspect `review-bundle.retry.json` for the objection record and the retry verdict.

## Reject Example

This example produces a reject verdict because command evidence records a failed test command.

```shell
node jury/bin/jury.mjs init --state-dir .jury-reject
node jury/bin/jury.mjs claim create --state-dir .jury-reject --id claim_reject_failed_tests --summary "change is ready" --scope jury
node jury/bin/jury.mjs evidence add --state-dir .jury-reject --id ev_failed_tests --claim claim_reject_failed_tests --type command --command "npm --prefix jury test" --exit-code 1
node jury/bin/jury.mjs judge --state-dir .jury-reject --claim claim_reject_failed_tests --out verdict.reject.json
if node jury/bin/jury.mjs gate --state-dir .jury-reject --claim claim_reject_failed_tests --verdict verdict.reject.json --json > gate.reject.json; then exit 1; else test $? -eq 1; fi
node jury/bin/jury.mjs bundle export --state-dir .jury-reject --claim claim_reject_failed_tests --out review-bundle.reject.json
node jury/bin/jury.mjs check --state-dir .jury-reject --strict
```

Inspect `gate.reject.json` for the failed decision and reason. Inspect `review-bundle.reject.json` for the failed command evidence and rejected verdict.
