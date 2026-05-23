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
- [examples/ci/jury-npm-publish.yml](examples/ci/jury-npm-publish.yml): release workflow example where npm publication depends on the package manifest check and a downloaded dry-run publication record.
- [examples/ci/fixtures/quickstart](examples/ci/fixtures/quickstart): expected `verdict.json`, `gate.json`, and `review-bundle.json` outputs.
- [examples/ci/fixtures/key-policy](examples/ci/fixtures/key-policy): signed bundle, public key, trusted key policy manifest, and untrusted-producer troubleshooting policy.
- [examples/ci/fixtures/key-policy-rotation](examples/ci/fixtures/key-policy-rotation): old and new producer keys trusted during a CI migration overlap window, plus a revoked-old policy that rejects stale old-key bundles after cutover.
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
```

The test suite covers the CI adoption guide, package publication notes, dry-run release publication checklist guidance, dry-run publication artifact handoff, dry-run publication summary output, dry-run package summary reviewer audit notes, stale dry-run artifact troubleshooting, npm token and provenance release checklist guidance, release metadata, package tarball manifest checks, quickstart, unsigned and signed GitHub Actions producer workflow commands, signed artifact download verification, downstream trusted-producer verification workflow, fixture synchronization, package manifest troubleshooting, troubleshooting failure examples, release checklist links, and this handoff note's references.

## Current Hardening Step

`bundle preflight --bundle review-bundle.json` validates imported bundles before local state is created or mutated. It reports bundle schema, producer metadata, provenance, record, cross-reference, and trust policy errors so CI consumers can reject third-party artifacts before `bundle import`.

## Trust Policy

Trust policy flags on `bundle preflight` and `bundle import` let CI allow or reject bundles by expected producer name, producer version, source, and revision pattern.

## Signed Attestations

Signed bundle attestations are available through `bundle export --attest-key`, `bundle export --attest-private-key`, `bundle preflight --verify-attestation-key`, `bundle preflight --verify-attestation-public-key`, and the matching `bundle import` verification flags. CI should combine attestation verification with trust policy flags before importing third-party bundles.

## Key Policy Manifests

`bundle preflight --key-policy` and `bundle import --key-policy` load a `jury.key_policy.v1` manifest containing trusted producer metadata and RSA public keys. Use it when CI needs one reviewed file for expected producers, source or revision constraints, key ids, and public keys. Key entries support `valid_from`, `valid_until`, `revoked_at`, and `revoked_reason` so CI can retire expired or compromised producer keys. Policy verification output identifies matching producer entries and every key under those producers, including not-selected, usable, verified, revoked, blocked-by-revocation, outside-validity, read-error, and signature-mismatch statuses.

## Next Hardening Step

Add release artifact retention expectations for dry-run publication records.
