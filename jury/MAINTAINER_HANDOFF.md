# Jury Maintainer Handoff

Jury v1 adoption is currently centered on a clean-checkout CI path that produces a verdict, gate result, and portable review bundle without external dependencies.

## Adoption Artifacts

- [QUICKSTART.md](QUICKSTART.md): local clean-checkout command sequence.
- [examples/ci/jury-review-gate.yml](examples/ci/jury-review-gate.yml): copyable GitHub Actions workflow.
- [examples/ci/fixtures/quickstart](examples/ci/fixtures/quickstart): expected `verdict.json`, `gate.json`, and `review-bundle.json` outputs.
- [MIGRATION.md](MIGRATION.md): artifact handoff and bundle replay path.
- [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md): release-readiness checklist.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md): failure-mode inspection and retry/reject examples.

## Validation

Run these from the repository root before handing Jury to another maintainer:

```shell
npm --prefix jury test
npm --prefix jury run check -- --state-dir /tmp/jury-maintainer-handoff --json
```

The test suite covers the quickstart, GitHub Actions workflow commands, fixture synchronization, troubleshooting failure examples, release checklist links, and this handoff note's references.

## Current Hardening Step

`bundle preflight --bundle review-bundle.json` validates imported bundles before local state is created or mutated. It reports bundle schema, producer metadata, provenance, record, cross-reference, and trust policy errors so CI consumers can reject third-party artifacts before `bundle import`.

## Trust Policy

Trust policy flags on `bundle preflight` and `bundle import` let CI allow or reject bundles by expected producer name, producer version, source, and revision pattern.

## Signed Attestations

Signed bundle attestations are available through `bundle export --attest-key`, `bundle export --attest-private-key`, `bundle preflight --verify-attestation-key`, `bundle preflight --verify-attestation-public-key`, and the matching `bundle import` verification flags. CI should combine attestation verification with trust policy flags before importing third-party bundles.

## Key Policy Manifests

`bundle preflight --key-policy` and `bundle import --key-policy` load a `jury.key_policy.v1` manifest containing trusted producer metadata and RSA public keys. Use it when CI needs one reviewed file for expected producers, source or revision constraints, key ids, and public keys.

## Next Hardening Step

Add key validity windows and revocation metadata so CI can retire compromised or expired producer keys.
