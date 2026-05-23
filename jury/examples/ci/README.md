# Jury CI Example

Jury can run as a local, dependency-free CI gate. The state directory is disposable, while the emitted `verdict.json` can be uploaded as a build artifact.

Copy [jury-review-gate.yml](jury-review-gate.yml) into `.github/workflows/` to use it as a GitHub Actions workflow. Copy [jury-trusted-bundle-verify.yml](jury-trusted-bundle-verify.yml) when a downstream workflow needs to verify and import a signed bundle from a trusted producer.

```yaml
name: Jury review gate

on:
  pull_request:

jobs:
  jury:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - name: Run Jury tests
        run: npm --prefix jury test
      - name: Build Jury verdict and bundle
        run: |
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
      - name: Upload Jury artifacts
        uses: actions/upload-artifact@v4
        with:
          name: jury-review
          path: |
            verdict.json
            review-bundle.json
            gate.json
            .jury/*.jsonl
```

The gate exits non-zero unless the verdict is `accept`. When `--claim` is present, the gate output includes unresolved blocking objections and missing fields so CI logs show the exact reason for failure. [fixtures/quickstart](fixtures/quickstart) shows the expected `verdict.json`, `review-bundle.json`, and `gate.json` outputs. `review-bundle.json` lets another job import and replay the same review state.

[fixtures/key-policy](fixtures/key-policy) provides a signed review bundle, public key, and `jury.key_policy.v1` manifest for copyable trusted-producer verification in a downstream job. [jury-trusted-bundle-verify.yml](jury-trusted-bundle-verify.yml) is the reusable workflow form of that handoff.

## Trusted Producer Handoff

Copy [fixtures/key-policy](fixtures/key-policy) into the downstream job workspace when one CI job needs to verify a bundle produced by another trusted job.

```yaml
jobs:
  trusted-jury:
    uses: ./.github/workflows/jury-trusted-bundle-verify.yml
    with:
      bundle-path: jury/examples/ci/fixtures/key-policy/review-bundle.signed.json
      key-policy-path: jury/examples/ci/fixtures/key-policy/jury-key-policy.json
      claim-id: claim_ci_change
```

In production, keep the private signing key only in the producing job. The downstream job needs the signed bundle, `jury-key-policy.json`, and the public key referenced by the policy.

Regenerate the checked-in key-policy fixtures with `npm --prefix jury run fixtures:key-policy`; CI can enforce drift with `npm --prefix jury run fixtures:key-policy:check`.
