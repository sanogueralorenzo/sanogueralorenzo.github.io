# Jury CI Artifact Migration

Jury starts with local append-only state in `.jury/`. To share results across CI jobs or systems, export the small artifacts first and keep the full state bundle only when deeper audit is needed.

## Minimal Path

1. Run Jury in CI with an explicit state directory:

```shell
node jury/bin/jury.mjs init --state-dir .jury
node jury/bin/jury.mjs claim create --state-dir .jury --id claim_ci_change --summary "pull request is ready" --scope jury --impact high
node jury/bin/jury.mjs claim transition --state-dir .jury --claim claim_ci_change --status screening
node jury/bin/jury.mjs claim transition --state-dir .jury --claim claim_ci_change --status in_review
node jury/bin/jury.mjs check add --state-dir .jury --id check_ci_tests --claim claim_ci_change --type verifier --summary "Jury tests must pass"
node jury/bin/jury.mjs evidence add --state-dir .jury --id ev_ci_tests --claim claim_ci_change --type command --command "npm --prefix jury test" --exit-code 0
node jury/bin/jury.mjs check update --state-dir .jury --id check_ci_tests --status passed --evidence ev_ci_tests --resolution "Jury tests passed"
node jury/bin/jury.mjs judge --state-dir .jury --claim claim_ci_change --out verdict.json
node jury/bin/jury.mjs gate --state-dir .jury --claim claim_ci_change --verdict verdict.json --json > gate.json
node jury/bin/jury.mjs bundle export --state-dir .jury --claim claim_ci_change --out review-bundle.json
node jury/bin/jury.mjs check --state-dir .jury --strict
```

2. Upload `verdict.json` as the required decision artifact.
3. Upload `gate.json` as the required gate result.
4. Upload `review-bundle.json` when another job or system needs to recreate the local review state.
5. Upload `.jury/*.jsonl` when reviewers need the raw append-only audit trail.
6. Upload `jury-demo-transcript.json` only for demos or examples.

## Round Trip

To consume a shared bundle in a fresh job:

```shell
node jury/bin/jury.mjs bundle preflight --bundle review-bundle.json
node jury/bin/jury.mjs init --state-dir .jury-imported
node jury/bin/jury.mjs bundle import --state-dir .jury-imported --bundle review-bundle.json --verdict-out imported-verdict.json
node jury/bin/jury.mjs gate --state-dir .jury-imported --claim claim_ci_change --verdict imported-verdict.json
node jury/bin/jury.mjs check --state-dir .jury-imported --strict
```

## Recommended Artifact Contract

- `verdict.json`: required. This is the decision record other systems should read.
- `gate.json`: required. This is the gate result CI systems should enforce.
- `review-bundle.json`: recommended for CI job handoff. This is a portable `jury.review_bundle.v1` snapshot of one claim, its related records, producer metadata, and source provenance.
- `.jury/claims.jsonl`: optional but useful for claim version history.
- `.jury/checks.jsonl`: optional but useful for required-review evidence.
- `.jury/evidence.jsonl`: optional and may contain command output; treat as potentially sensitive.
- `.jury/objections.jsonl`: optional but useful for unresolved risk review.
- `.jury/waivers.jsonl`: optional but required when a verdict references waivers.
- `.jury/verdicts.jsonl`: optional append-only verdict history.

## Compatibility

Use [release.json](release.json) to discover supported schema files, state files, export examples, and CLI commands. Consumers should reject artifacts with unknown `schema_version` values instead of guessing.

Run `bundle preflight` before `bundle import` for third-party bundles. Preflight reports all bundle validation errors it can find and exits before creating or mutating `.jury/` state. Import consumers should inspect `producer.name`, `producer.version`, `provenance.source`, and `provenance.revision` before trusting the bundle.
