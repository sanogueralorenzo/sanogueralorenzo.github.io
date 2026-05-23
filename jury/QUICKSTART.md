# Jury Quickstart

This quickstart runs from a clean checkout with Node.js 20 or newer.

```shell
npm --prefix jury test
node jury/bin/jury.mjs init --state-dir .jury
node jury/bin/jury.mjs claim create --state-dir .jury --id claim_ci_change --summary "pull request is ready" --scope jury --impact high
node jury/bin/jury.mjs claim transition --state-dir .jury --claim claim_ci_change --status screening
node jury/bin/jury.mjs claim transition --state-dir .jury --claim claim_ci_change --status in_review
node jury/bin/jury.mjs check add --state-dir .jury --id check_ci_tests --claim claim_ci_change --type verifier --summary "Jury tests must pass"
node jury/bin/jury.mjs evidence add --state-dir .jury --id ev_ci_tests --claim claim_ci_change --type command --command "npm --prefix jury test" --exit-code 0
node jury/bin/jury.mjs critic run --state-dir .jury --claim claim_ci_change --role tests
node jury/bin/jury.mjs critic run --state-dir .jury --claim claim_ci_change --role security
node jury/bin/jury.mjs critic run --state-dir .jury --claim claim_ci_change --role scope --changed-files jury/bin/jury.mjs,jury/test/jury.test.mjs
node jury/bin/jury.mjs check update --state-dir .jury --id check_ci_tests --status passed --evidence ev_ci_tests --resolution "Jury tests passed"
node jury/bin/jury.mjs judge --state-dir .jury --claim claim_ci_change --out verdict.json
node jury/bin/jury.mjs gate --state-dir .jury --claim claim_ci_change --verdict verdict.json --json > gate.json
node jury/bin/jury.mjs bundle export --state-dir .jury --claim claim_ci_change --out review-bundle.json
node jury/bin/jury.mjs check --state-dir .jury --strict
```

Expected artifacts:

- `verdict.json`: the gate decision.
- `review-bundle.json`: portable `jury.review_bundle.v1` state for another CI job or reviewer.
- `gate.json`: the CI gate result.
- `.jury/*.jsonl`: local append-only audit state.

To replay the portable bundle in a fresh state directory:

```shell
node jury/bin/jury.mjs init --state-dir .jury-imported
node jury/bin/jury.mjs bundle import --state-dir .jury-imported --bundle review-bundle.json --verdict-out imported-verdict.json
node jury/bin/jury.mjs gate --state-dir .jury-imported --claim claim_ci_change --verdict imported-verdict.json
node jury/bin/jury.mjs check --state-dir .jury-imported --strict
```
