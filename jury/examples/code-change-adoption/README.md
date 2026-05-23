# Jury Code-Change Adoption Fixture

This fixture proves the smallest code-change adoption path that still produces reusable retry evidence and then resolves it into acceptance. It starts from empty state, creates a scoped code-change claim, attaches passing command evidence, runs a deterministic critic, emits a retry verdict, gates on that verdict, exports a portable retry bundle, records the scope correction, resolves the objection, emits an accept verdict, gates on acceptance, and exports a portable accepted bundle.

## Code-Change Adoption Flow

```shell
rm -rf .jury-code-change verdict.retry.json gate.retry.json review-bundle.retry.json verdict.accept.json gate.accept.json review-bundle.accept.json
node jury/bin/jury.mjs init --state-dir .jury-code-change --json
node jury/bin/jury.mjs claim create --state-dir .jury-code-change --id claim_checkout_ready --summary "checkout code change is ready" --scope jury --impact high --json
node jury/bin/jury.mjs evidence add --state-dir .jury-code-change --id ev_jury_tests --claim claim_checkout_ready --type command --command "npm --prefix jury test" --exit-code 0 --json
node jury/bin/jury.mjs critic run --state-dir .jury-code-change --claim claim_checkout_ready --role scope --changed-files jury/bin/jury.mjs,docs/checkout-notes.md --json
node jury/bin/jury.mjs judge --state-dir .jury-code-change --claim claim_checkout_ready --out verdict.retry.json --json
node jury/bin/jury.mjs gate --state-dir .jury-code-change --claim claim_checkout_ready --verdict verdict.retry.json --json > gate.retry.json || test "$?" -eq 1
node jury/bin/jury.mjs bundle export --state-dir .jury-code-change --claim claim_checkout_ready --out review-bundle.retry.json --source local --revision code-change-adoption-fixture --json
node jury/bin/jury.mjs bundle preflight --bundle review-bundle.retry.json --json
JURY_NOW=2026-05-23T00:00:01.000Z node jury/bin/jury.mjs evidence add --state-dir .jury-code-change --id ev_scope_corrected --claim claim_checkout_ready --type manual --summary "changed files are limited to the jury scope" --source "changed-files:jury/bin/jury.mjs" --status passed --json
JURY_NOW=2026-05-23T00:00:01.000Z node jury/bin/jury.mjs objection resolve --state-dir .jury-code-change --id obj_claim_checkout_ready_scope_out_of_scope_changes --resolution "Removed docs/checkout-notes.md from the change set and reran scope review with only jury/bin/jury.mjs." --json
JURY_NOW=2026-05-23T00:00:01.000Z node jury/bin/jury.mjs critic run --state-dir .jury-code-change --claim claim_checkout_ready --role scope --changed-files jury/bin/jury.mjs --json
JURY_NOW=2026-05-23T00:00:01.000Z node jury/bin/jury.mjs judge --state-dir .jury-code-change --claim claim_checkout_ready --out verdict.accept.json --json
JURY_NOW=2026-05-23T00:00:01.000Z node jury/bin/jury.mjs gate --state-dir .jury-code-change --claim claim_checkout_ready --verdict verdict.accept.json --json > gate.accept.json
JURY_NOW=2026-05-23T00:00:01.000Z node jury/bin/jury.mjs bundle export --state-dir .jury-code-change --claim claim_checkout_ready --out review-bundle.accept.json --source local --revision code-change-adoption-fixture --json
JURY_NOW=2026-05-23T00:00:01.000Z node jury/bin/jury.mjs bundle preflight --bundle review-bundle.accept.json --json
node jury/bin/jury.mjs check --state-dir .jury-code-change --strict --json
```

## Fixture Artifacts

- [verdict.retry.json](verdict.retry.json): retry verdict with the exact next action raised by the scope critic.
- [gate.retry.json](gate.retry.json): failing gate output that preserves the retry decision, unresolved objection, and next action for CI.
- [review-bundle.retry.json](review-bundle.retry.json): portable `jury.review_bundle.v1` containing the claim, command evidence, critic objection, and retry verdict.
- [verdict.accept.json](verdict.accept.json): accept verdict after the scope correction evidence resolves the retry objection.
- [gate.accept.json](gate.accept.json): passing gate output proving the accepted verdict is mergeable.
- [review-bundle.accept.json](review-bundle.accept.json): portable `jury.review_bundle.v1` containing retry history, resolution evidence, resolved objection state, and accepted verdict.

The intentionally out-of-scope `docs/checkout-notes.md` changed file keeps the retry fixture actionable. The accepted fixture then records `ev_scope_corrected`, resolves `obj_claim_checkout_ready_scope_out_of_scope_changes`, reruns the scope critic with only `jury/bin/jury.mjs`, and preserves both the retry and accepted verdicts in the final bundle.
