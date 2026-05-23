# Jury CI Artifact Migration

Jury starts with local append-only state in `.jury/`. To share results across CI jobs or systems, export the small artifacts first and keep the full state bundle only when deeper audit is needed.

## Minimal Path

1. Run Jury in CI with an explicit state directory:

```shell
node jury/bin/jury.mjs init --state-dir .jury
node jury/bin/jury.mjs claim create --state-dir .jury --id claim_ci_change --summary "pull request is ready" --scope jury
node jury/bin/jury.mjs check add --state-dir .jury --id check_ci_tests --claim claim_ci_change --type verifier --summary "Jury tests must pass"
node jury/bin/jury.mjs evidence add --state-dir .jury --claim claim_ci_change --type command --run "node --test jury/test/*.test.mjs"
node jury/bin/jury.mjs check update --state-dir .jury --id check_ci_tests --status passed --resolution "Jury tests passed"
node jury/bin/jury.mjs judge --state-dir .jury --claim claim_ci_change --out verdict.json
node jury/bin/jury.mjs gate --state-dir .jury --claim claim_ci_change --verdict verdict.json
node jury/bin/jury.mjs check --state-dir .jury --strict
```

2. Upload `verdict.json` as the required gate artifact.
3. Upload `.jury/*.jsonl` when reviewers need the full audit trail.
4. Upload `jury-demo-transcript.json` only for demos or examples.

## Recommended Artifact Contract

- `verdict.json`: required. This is the decision record other systems should read.
- `.jury/claims.jsonl`: optional but useful for claim version history.
- `.jury/checks.jsonl`: optional but useful for required-review evidence.
- `.jury/evidence.jsonl`: optional and may contain command output; treat as potentially sensitive.
- `.jury/objections.jsonl`: optional but useful for unresolved risk review.
- `.jury/waivers.jsonl`: optional but required when a verdict references waivers.
- `.jury/verdicts.jsonl`: optional append-only verdict history.

## Compatibility

Use [release.json](release.json) to discover supported schema files, state files, export examples, and CLI commands. Consumers should reject artifacts with unknown `schema_version` values instead of guessing.
