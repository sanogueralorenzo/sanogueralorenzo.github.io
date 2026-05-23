# Jury CI Example

Jury can run as a local, dependency-free CI gate. The state directory is disposable, while the emitted `verdict.json` can be uploaded as a build artifact.

Use [../../CI_ADOPTION.md](../../CI_ADOPTION.md) to choose the right workflow. Copy [jury-review-gate.yml](jury-review-gate.yml) into `.github/workflows/` to use it as a GitHub Actions workflow. Copy [jury-signed-review-gate.yml](jury-signed-review-gate.yml) when the producing job must sign the live bundle with `secrets.JURY_CI_PRIVATE_KEY`. Copy [jury-signed-artifact-handoff.yml](jury-signed-artifact-handoff.yml) when a second job should download and verify the signed artifact. Copy [jury-trusted-bundle-verify.yml](jury-trusted-bundle-verify.yml) when a downstream workflow needs to verify and import a signed bundle from a trusted producer. Copy [jury-package-manifest-check.yml](jury-package-manifest-check.yml) when publication CI should fail before packaging omits Jury CI adoption metadata. Copy [jury-npm-publish.yml](jury-npm-publish.yml) when npm publication should require that manifest check before `npm publish`.

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

[fixtures/key-policy](fixtures/key-policy) provides a signed review bundle, public key, and `jury.key_policy.v1` manifest for copyable trusted-producer verification in a downstream job. [jury-signed-review-gate.yml](jury-signed-review-gate.yml) signs the producer bundle with an external CI private key secret, and [jury-trusted-bundle-verify.yml](jury-trusted-bundle-verify.yml) is the reusable workflow form of the downstream handoff.

[fixtures/key-policy-rotation](fixtures/key-policy-rotation) shows a rotation window where downstream CI trusts old and new producer keys while jobs migrate from `ci-old` to `ci-new`.

## Signed Producer Workflow

Use [jury-signed-review-gate.yml](jury-signed-review-gate.yml) when the producing job should emit `review-bundle.signed.json` from the live CI state. Configure `JURY_CI_PRIVATE_KEY` as a repository or organization secret containing a PEM RSA private key. Optionally set `JURY_ATTESTATION_KEY_ID` as a repository variable so the downstream `jury-key-policy.json` can select the matching public key.

The workflow writes the key to `$RUNNER_TEMP`, signs with `--attest-private-key`, runs `bundle preflight --require-attestation true`, removes the key in an `always()` cleanup step, and uploads only the signed bundle, verdict, gate output, and append-only state.

## Artifact Handoff Workflow

[jury-signed-artifact-handoff.yml](jury-signed-artifact-handoff.yml) keeps producer and consumer jobs in one copyable workflow. The producer uploads `review-bundle.signed.json`; the downstream job uses `actions/download-artifact@v4`, verifies the downloaded bundle with `jury-key-policy.json`, imports the trusted state, and gates the imported verdict.

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

## Package Publication Check

[jury-package-manifest-check.yml](jury-package-manifest-check.yml) is a reusable workflow for release jobs. It runs `npm --prefix "$JURY_PACKAGE_DIR" run package:manifest:check` before publication, so CI rejects tarballs that omit `release.json`, `CI_ADOPTION.md`, supported workflow files, or the required package files in [../../PUBLISHING.md](../../PUBLISHING.md).

[jury-npm-publish.yml](jury-npm-publish.yml) shows a release workflow where `package-release-fixtures` runs `npm --prefix "$JURY_PACKAGE_DIR" run fixtures:package-release:check` before any publication dry run, uploads `jury-package-release-evidence` with rollback and replacement audit examples, `package-release-evidence-replay` downloads that artifact and replays it with `--fixture-dir`, `dry-run-publication` has `needs: package-manifest` and `needs: package-release-evidence-replay`, uploads `jury-package-dry-run`, keeps both package release artifacts with `retention-days: 90`, and `publish` downloads and verifies that artifact before the `NODE_AUTH_TOKEN` publish step runs `npm publish --provenance --access public`. If replay fails, [../../TROUBLESHOOTING.md](../../TROUBLESHOOTING.md) shows how to inspect `jury-package-release-evidence` files and `JURY_PACKAGE_RELEASE_EVIDENCE_DIR`. Failed and replacement releases must promote those temporary CI artifacts into the release record or incident archive for at least 180 days after replacement downstream verification passes, including retained artifact provenance for workflow, run id, source revision, source job, retention days, and uploaded files. Use `--manifest-out retained-package-release-evidence-manifest.json` to export the retained archive handoff manifest and `--verify-manifest retained-package-release-evidence-manifest.json` to verify it before closure. The workflow requires `dry_run_reviewer`, and the verification step writes the checked `packageVersion`, `tarballName`, and `reviewedBy` to `GITHUB_STEP_SUMMARY`.

After publication, compare the retained `jury-pack-dry-run-record.json` with `npm view @sanogueralorenzo/jury@<packageVersion> version dist.tarball --json`; the registry version must match `packageVersion`, and the registry tarball URL must end with `tarballName`.
