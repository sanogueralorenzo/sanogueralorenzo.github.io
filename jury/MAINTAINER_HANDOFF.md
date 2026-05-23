# Jury Maintainer Handoff

Jury v1 adoption is currently centered on a clean-checkout CI path that produces a verdict, gate result, and portable review bundle without external dependencies.

## Adoption Artifacts

- [QUICKSTART.md](QUICKSTART.md): local clean-checkout command sequence.
- [CI_ADOPTION.md](CI_ADOPTION.md): concise workflow chooser for unsigned, signed, artifact handoff, and reusable downstream CI paths.
- [examples/ci/jury-review-gate.yml](examples/ci/jury-review-gate.yml): copyable GitHub Actions workflow.
- [examples/ci/jury-signed-review-gate.yml](examples/ci/jury-signed-review-gate.yml): producing-job workflow that signs a live bundle with an external CI private key secret.
- [examples/ci/jury-signed-artifact-handoff.yml](examples/ci/jury-signed-artifact-handoff.yml): two-job workflow that downloads the signed producer artifact and verifies it with the key policy.
- [examples/ci/jury-trusted-bundle-verify.yml](examples/ci/jury-trusted-bundle-verify.yml): reusable downstream workflow for signed trusted-producer bundle verification.
- [examples/ci/jury-package-manifest-check.yml](examples/ci/jury-package-manifest-check.yml): reusable workflow step that runs the package manifest check before publication.
- [examples/ci/jury-npm-publish.yml](examples/ci/jury-npm-publish.yml): release workflow example where npm publication depends on the package manifest check, package release evidence fixture validation, a downloaded and replayed release evidence audit artifact, and a downloaded dry-run publication record.
- [examples/ci/fixtures/quickstart](examples/ci/fixtures/quickstart): expected `verdict.json`, `gate.json`, and `review-bundle.json` outputs.
- [examples/ci/fixtures/key-policy](examples/ci/fixtures/key-policy): signed bundle, public key, trusted key policy manifest, and untrusted-producer troubleshooting policy.
- [examples/ci/fixtures/key-policy-rotation](examples/ci/fixtures/key-policy-rotation): old and new producer keys trusted during a CI migration overlap window, plus a revoked-old policy that rejects stale old-key bundles after cutover.
- [examples/ci/fixtures/package-release](examples/ci/fixtures/package-release): local package release evidence examples for failed publication rollback and replacement patch supersedence audits.
- [schemas/package-release-evidence.schema.json](schemas/package-release-evidence.schema.json): JSON schema contract for package release evidence audit files.
- [scripts/validate-package-release-fixtures.mjs](scripts/validate-package-release-fixtures.mjs): local schema and relationship check for the package release evidence fixtures.
- [MIGRATION.md](MIGRATION.md): artifact handoff and bundle replay path.
- [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md): release-readiness checklist.
- [PUBLISHING.md](PUBLISHING.md): package publication notes for preserving the CI adoption metadata contract.
- [release.json](release.json): machine-readable CI adoption guide path and workflow variant metadata.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md): failure-mode inspection and retry/reject examples.

## Validation

Run these from the repository root before handing Jury to another maintainer:

```shell
npm --prefix jury test
npm --prefix jury run check -- --state-dir /tmp/jury-maintainer-handoff --json
npm --prefix jury run package:manifest:check
npm --prefix jury run fixtures:package-release:check
```

The test suite covers the CI adoption guide, package publication notes, dry-run release publication checklist guidance, dry-run publication artifact handoff, dry-run artifact retention expectations, package release evidence artifact upload guidance, package release evidence artifact download and replay guidance, package release evidence replay failure troubleshooting for package rollback and replacement audits, package release evidence retention policy for failed and replacement release artifacts, package release artifact provenance checks for retained failed and replacement evidence, post-publication package metadata comparison guidance, downstream verification rollback notes, replacement patch supersedence evidence, package release evidence fixture examples, package release evidence schema validation, package release fixture workflow gating, dry-run publication summary output, dry-run package summary reviewer audit notes, stale dry-run artifact troubleshooting, npm token and provenance release checklist guidance, release metadata, package tarball manifest checks, quickstart, unsigned and signed GitHub Actions producer workflow commands, signed artifact download verification, downstream trusted-producer verification workflow, fixture synchronization, package manifest troubleshooting, troubleshooting failure examples, release checklist links, and this handoff note's references.

## Current Hardening Step

Package release artifact provenance checks now require retained failed and replacement evidence to record the GitHub Actions source, `jury-npm-publish.yml` workflow, run id, source revision, source jobs, `retentionDays: 90`, and uploaded file list for `jury-package-dry-run` and `jury-package-release-evidence`.

## Retention Policy

Package release evidence retention defines temporary CI artifact retention and long-term release record expectations for failed and replacement releases. `jury-package-dry-run` and `jury-package-release-evidence` stay available as CI artifacts for 90 days, while failed/replacement evidence must be promoted to the release record or incident archive until at least 180 days after replacement downstream verification passes.

## Replay Troubleshooting

Package release evidence replay troubleshooting now covers `package-release-evidence-replay` failures for rollback and replacement audits. It documents local `--fixture-dir` replay, required `jury-package-release-evidence` files, missing artifact diagnostics, schema failures such as `replacement-patch-audit.json.checks is required`, and `JURY_PACKAGE_RELEASE_EVIDENCE_DIR` path mistakes before `dry-run-publication`.

## Bundle Preflight

`bundle preflight --bundle review-bundle.json` validates imported bundles before local state is created or mutated. It reports bundle schema, producer metadata, provenance, record, cross-reference, and trust policy errors so CI consumers can reject third-party artifacts before `bundle import`.

## Trust Policy

Trust policy flags on `bundle preflight` and `bundle import` let CI allow or reject bundles by expected producer name, producer version, source, and revision pattern.

## Signed Attestations

Signed bundle attestations are available through `bundle export --attest-key`, `bundle export --attest-private-key`, `bundle preflight --verify-attestation-key`, `bundle preflight --verify-attestation-public-key`, and the matching `bundle import` verification flags. CI should combine attestation verification with trust policy flags before importing third-party bundles.

## Key Policy Manifests

`bundle preflight --key-policy` and `bundle import --key-policy` load a `jury.key_policy.v1` manifest containing trusted producer metadata and RSA public keys. Use it when CI needs one reviewed file for expected producers, source or revision constraints, key ids, and public keys. Key entries support `valid_from`, `valid_until`, `revoked_at`, and `revoked_reason` so CI can retire expired or compromised producer keys. Policy verification output identifies matching producer entries and every key under those producers, including not-selected, usable, verified, revoked, blocked-by-revocation, outside-validity, read-error, and signature-mismatch statuses.

## Next Hardening Step

Add retained package release evidence manifest export for failed and replacement release archives.
