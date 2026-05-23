# Jury Code-Change Adoption Fixture

This fixture proves the smallest code-change adoption path that still produces reusable retry evidence. It starts from empty state, creates a scoped code-change claim, attaches passing command evidence, runs a deterministic critic, emits a retry verdict, gates on that verdict, and exports a portable review bundle.

## Code-Change Adoption Flow

```shell
rm -rf .jury-code-change verdict.retry.json gate.retry.json review-bundle.retry.json
node jury/bin/jury.mjs init --state-dir .jury-code-change --json
node jury/bin/jury.mjs claim create --state-dir .jury-code-change --id claim_checkout_ready --summary "checkout code change is ready" --scope jury --impact high --json
node jury/bin/jury.mjs evidence add --state-dir .jury-code-change --id ev_jury_tests --claim claim_checkout_ready --type command --command "npm --prefix jury test" --exit-code 0 --json
node jury/bin/jury.mjs critic run --state-dir .jury-code-change --claim claim_checkout_ready --role scope --changed-files jury/bin/jury.mjs,docs/checkout-notes.md --json
node jury/bin/jury.mjs judge --state-dir .jury-code-change --claim claim_checkout_ready --out verdict.retry.json --json
node jury/bin/jury.mjs gate --state-dir .jury-code-change --claim claim_checkout_ready --verdict verdict.retry.json --json > gate.retry.json || test "$?" -eq 1
node jury/bin/jury.mjs bundle export --state-dir .jury-code-change --claim claim_checkout_ready --out review-bundle.retry.json --source local --revision code-change-adoption-fixture --json
node jury/bin/jury.mjs bundle preflight --bundle review-bundle.retry.json --json
node jury/bin/jury.mjs check --state-dir .jury-code-change --strict --json
```

## Fixture Artifacts

- [verdict.retry.json](verdict.retry.json): retry verdict with the exact next action raised by the scope critic.
- [gate.retry.json](gate.retry.json): failing gate output that preserves the retry decision, unresolved objection, and next action for CI.
- [review-bundle.retry.json](review-bundle.retry.json): portable `jury.review_bundle.v1` containing the claim, command evidence, critic objection, and retry verdict.

The intentionally out-of-scope `docs/checkout-notes.md` changed file keeps the fixture actionable: the next run must either narrow the changed files to the `jury` scope, expand the claim scope with evidence, or resolve the objection with a reviewed reason before acceptance.
