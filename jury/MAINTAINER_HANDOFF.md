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
- [examples/ci/jury-npm-publish.yml](examples/ci/jury-npm-publish.yml): release workflow example where npm publication depends on the package manifest check, package release evidence fixture validation, a downloaded and replayed release evidence audit artifact, a downloaded and replayed retained archive manifest artifact, and a downloaded dry-run publication record.
- [examples/ci/fixtures/quickstart](examples/ci/fixtures/quickstart): expected `verdict.json`, `gate.json`, and `review-bundle.json` outputs.
- [examples/ci/fixtures/key-policy](examples/ci/fixtures/key-policy): signed bundle, public key, trusted key policy manifest, and untrusted-producer troubleshooting policy.
- [examples/ci/fixtures/key-policy-rotation](examples/ci/fixtures/key-policy-rotation): old and new producer keys trusted during a CI migration overlap window, plus a revoked-old policy that rejects stale old-key bundles after cutover.
- [examples/ci/fixtures/package-release](examples/ci/fixtures/package-release): local package release evidence examples for failed publication rollback, replacement patch supersedence audits, retained release archive manifest fixture, and archive drift remediation audit record.
- [schemas/package-release-archive-manifest.schema.json](schemas/package-release-archive-manifest.schema.json): JSON schema contract for retained package release archive manifests.
- [schemas/package-release-evidence.schema.json](schemas/package-release-evidence.schema.json): JSON schema contract for package release evidence audit files.
- [schemas/package-release-remediation-audit.schema.json](schemas/package-release-remediation-audit.schema.json): JSON schema contract for retained archive drift remediation audit records.
- [schemas/package-release-replay-summary-diagnostics-retention-handoff.schema.json](schemas/package-release-replay-summary-diagnostics-retention-handoff.schema.json): JSON schema contract for replay summary diagnostics retention handoff records.
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
npm --prefix jury run fixtures:package-release:drift
```

The test suite covers the CI adoption guide, package publication notes, dry-run release publication checklist guidance, dry-run publication artifact handoff, dry-run artifact retention expectations, package release evidence artifact upload guidance, package release evidence artifact download and replay guidance, package release evidence replay failure troubleshooting for package rollback and replacement audits, package release evidence retention policy for failed and replacement release artifacts, package release artifact provenance checks for retained failed and replacement evidence, retained package release evidence manifest export, schema validation, verification, archive drift checking, archive drift remediation audit records, CI handoff, replay summary retention handoff, replay summary diagnostics retention handoff, replay summary diagnostics retention handoff CI replay enforcement, replay summary diagnostics retention handoff CI replay enforcement failure troubleshooting, replay summary diagnostics retention handoff schema failure troubleshooting, replay summary retention failure troubleshooting, and replay troubleshooting for failed and replacement release archives, post-publication package metadata comparison guidance, downstream verification rollback notes, replacement patch supersedence evidence, package release evidence fixture examples, package release evidence schema validation, package release fixture workflow gating, dry-run publication summary output, dry-run package summary reviewer audit notes, stale dry-run artifact troubleshooting, npm token and provenance release checklist guidance, release metadata, package tarball manifest checks, quickstart, unsigned and signed GitHub Actions producer workflow commands, signed artifact download verification, downstream trusted-producer verification workflow, fixture synchronization, package manifest troubleshooting, troubleshooting failure examples, release checklist links, and this handoff note's references.

## Current Hardening Step

Retained package release evidence manifest export is available through `npm --prefix jury run fixtures:package-release:check -- --fixture-dir <retained-evidence-dir> --manifest-out retained-package-release-evidence-manifest.json`. The exported `jury.package_release_archive_manifest.v1` file combines failed publication evidence, replacement patch evidence, retention requirements, artifact provenance, and archive evidence digests for release archive handoff. Export and verification validate the file against [schemas/package-release-archive-manifest.schema.json](schemas/package-release-archive-manifest.schema.json). Verify the archived manifest with `--verify-manifest retained-package-release-evidence-manifest.json` before closing the failed release record.

## Manifest CI Handoff

The npm publication example exports `retained-package-release-evidence-manifest.json`, uploads it as the `jury-package-release-archive-manifest` artifact, downloads it in `package-release-evidence-replay`, and verifies it with `--verify-manifest "$JURY_PACKAGE_RELEASE_MANIFEST_PATH"` before `dry-run-publication`.

## Remediation Audit CI Handoff

The same publication example uploads [examples/ci/fixtures/package-release/archive-drift-remediation-audit.json](examples/ci/fixtures/package-release/archive-drift-remediation-audit.json) inside the `jury-package-release-evidence` artifact. The `package-release-evidence-replay` job downloads that artifact and reruns `fixtures:package-release:check`, so missing remediation audit records, failed-publication drift, replacement-patch drift, restored evidence, verification commands, and maintainer approval are checked before `dry-run-publication`.

## Replay Artifact Summary

The replay job writes a `GITHUB_STEP_SUMMARY` section named `Jury package release replay`. It records the failed package version, failed tarball name, replacement package version, failed archive evidence, replacement archive evidence, and remediation approver before `dry-run-publication`. The same content is saved as `jury-package-release-replay-summary.md` and uploaded as the `jury-package-release-replay-summary` artifact with `retention-days: 90`.

## Replay Summary CI Workflow Diagnostics

The replay job also writes `jury-package-release-replay-summary-diagnostics.json` with `jury.package_release_replay_summary_diagnostics.v1`. The diagnostics record captures the `package-release-evidence-replay` source job, summary artifact name, summary file name, failed package version, failed tarball name, replacement package version, failed archive evidence, replacement archive evidence, remediation approver, and checked summary lines. The fixture validator loads [schemas/package-release-replay-summary-diagnostics.schema.json](schemas/package-release-replay-summary-diagnostics.schema.json) and checks [examples/ci/fixtures/package-release/jury-package-release-replay-summary-diagnostics.json](examples/ci/fixtures/package-release/jury-package-release-replay-summary-diagnostics.json) so CI workflow summary diagnostics stay tied to failed and replacement release archives.

## Replay Summary Diagnostics Retention Handoff

The replay job records `jury-package-release-replay-summary-diagnostics-retention-handoff.json` with `jury.package_release_replay_summary_diagnostics_retention_handoff.v1`. The handoff captures the replay summary source artifact, `package-release-evidence-replay` source job, `retentionDays: 90`, diagnostics schema version, retained diagnostics file, summary file, companion retained records, failed package version, failed tarball name, replacement package version, workflow run id, source revision, and reviewing maintainer. The fixture validator loads [schemas/package-release-replay-summary-diagnostics-retention-handoff.schema.json](schemas/package-release-replay-summary-diagnostics-retention-handoff.schema.json) and checks [examples/ci/fixtures/package-release/jury-package-release-replay-summary-diagnostics-retention-handoff.json](examples/ci/fixtures/package-release/jury-package-release-replay-summary-diagnostics-retention-handoff.json) before failed or replacement release archives close.

## Replay Summary Diagnostics Retention Handoff CI Replay Enforcement

The replay job now runs `Replay Jury package release replay diagnostics retention handoff` after generating the diagnostics retention handoff and before uploading `jury-package-release-replay-summary`. The step rereads the generated handoff, retained manifest, diagnostics JSON, retained fixture handoff, archive drift remediation audit, and replay summary artifact provenance. It fails before `dry-run-publication` if the handoff no longer matches failed or replacement package identity, run id, source revision, reviewing maintainer, retained companion files, or the uploaded replay summary artifact file list.

## Replay Summary Diagnostics Retention Handoff CI Replay Enforcement Failure Troubleshooting

Replay summary diagnostics retention handoff CI replay enforcement failure troubleshooting now covers missing or misordered `Replay Jury package release replay diagnostics retention handoff` workflow steps and generated handoff mismatches. It documents workflow ordering checks that prove replay runs after handoff generation but before summary upload and `dry-run-publication`, plus a local replay command that compares the generated handoff with retained failed and replacement archive evidence.

## Replay Summary Retention Handoff

Failed and replacement release records must promote `jury-package-release-replay-summary.md` from the `jury-package-release-replay-summary` artifact with the retained `jury-package-release-evidence`, `jury-package-release-archive-manifest`, and `archive-drift-remediation-audit.json` records. The retained artifact provenance must record the `package-release-evidence-replay` source job, workflow run id, source revision, `retentionDays: 90`, and uploaded file list before closing the release or incident archive.

## Release Archive Fixture

The package release fixture directory includes [examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json](examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json). Keep it synchronized with `rollback-audit.json`, `replacement-patch-audit.json`, the dry-run record, npm metadata, downstream gates, retention policy, and artifact provenance by regenerating it with `--manifest-out examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json` and verifying it with `--verify-manifest examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json`.

## Archive Drift Check

Run `npm --prefix jury run fixtures:package-release:drift` before handing off package release fixtures. It verifies the checked-in retained archive manifest still matches the failed publication archive evidence, replacement patch archive evidence, retention policy, artifact provenance, and archive evidence digests.

## Archive Drift Remediation

When archive drift appears, restore the changed failed or replacement archive evidence before regenerating the retained manifest. Use [TROUBLESHOOTING.md](TROUBLESHOOTING.md) to identify whether the drift belongs to failed publication evidence, replacement patch evidence, or the dry-run package identity, then regenerate with `--manifest-out`, review the diff, rerun `--verify-manifest`, and record the approving maintainer in the release or incident record before replacing the archived manifest.

## Remediation Audit Record

The package release fixture directory includes [examples/ci/fixtures/package-release/archive-drift-remediation-audit.json](examples/ci/fixtures/package-release/archive-drift-remediation-audit.json). It records failed-publication drift, replacement-patch drift, restored evidence, verification commands, manifest regeneration, diff review, and maintainer approval before archived manifest replacement.

## Manifest Replay Troubleshooting

Retained package release evidence manifest replay troubleshooting now covers `--verify-manifest` failures for failed and replacement release archives. It documents local replay against the retained evidence directory, retained file presence checks, manifest identity inspection, required archive evidence checks, missing retained manifest diagnostics, missing retained file diagnostics, missing retention artifact diagnostics, missing provenance artifact diagnostics, schema failures such as `schema_version must equal jury.package_release_archive_manifest.v1`, and mismatch failures such as `does not match retained package release evidence`.

## Provenance Checks

Package release artifact provenance checks require retained failed and replacement evidence to record the GitHub Actions source, `jury-npm-publish.yml` workflow, run id, source revision, source jobs, `retentionDays: 90`, and uploaded file list for `jury-package-dry-run` and `jury-package-release-evidence`.

## Retention Policy

Package release evidence retention defines temporary CI artifact retention and long-term release record expectations for failed and replacement releases. `jury-package-dry-run` and `jury-package-release-evidence` stay available as CI artifacts for 90 days, while failed/replacement evidence must be promoted to the release record or incident archive until at least 180 days after replacement downstream verification passes.

## Replay Troubleshooting

Package release evidence replay troubleshooting now covers `package-release-evidence-replay` failures for rollback and replacement audits. It documents local `--fixture-dir` replay, required `jury-package-release-evidence` files, missing artifact diagnostics, schema failures such as `replacement-patch-audit.json.checks is required`, and `JURY_PACKAGE_RELEASE_EVIDENCE_DIR` path mistakes before `dry-run-publication`.

## Remediation Audit Replay Troubleshooting

Remediation audit replay troubleshooting now includes executable examples for missing `approvedBy` and missing verification commands. Use them when `archive-drift-remediation-audit.json` is present but replay rejects the approval or command evidence required before replacing a retained manifest.

## Replay Artifact Summary Troubleshooting

Replay artifact summary troubleshooting now includes executable examples that reconstruct the expected failed/replacement archive summary from the retained evidence and compare it with the saved `GITHUB_STEP_SUMMARY` output. Use them when the replay job passes but the release page does not show the failed package identity, replacement package identity, retained archive evidence lists, or remediation approver.

## Replay Summary CI Workflow Diagnostics Troubleshooting

Replay summary CI workflow diagnostics troubleshooting now includes executable examples that validate the diagnostics JSON shape and compare it with the retained manifest, remediation audit, and saved summary file. Use them when `jury-package-release-replay-summary-diagnostics.json` is missing, malformed, or no longer proves the failed and replacement archive evidence behind the workflow summary.

## Replay Summary Diagnostics Retention Handoff Troubleshooting

Replay summary diagnostics retention handoff troubleshooting now includes executable examples that validate the handoff JSON shape and compare it with the retained manifest, diagnostics JSON, replay summary artifact provenance, and archive approval. Use them when `jury-package-release-replay-summary-diagnostics-retention-handoff.json` is missing, malformed, or no longer proves diagnostics retention for failed and replacement release archives.

## Replay Summary Diagnostics Retention Handoff Schema Failure Troubleshooting

Replay summary diagnostics retention handoff schema failure troubleshooting now covers validator failures for `jury-package-release-replay-summary-diagnostics-retention-handoff.json`. It documents local `fixtures:package-release:check` replay, schema-critical field inspection, retained manifest relationship checks for failed package version, failed tarball name, replacement package version, workflow run id, source revision, and maintainer approval checks against `archive-drift-remediation-audit.json` before a failed or replacement release archive closes.

## Replay Summary Retention Failure Troubleshooting

Replay summary retention failure troubleshooting now covers missing `jury-package-release-replay-summary.md`, missing `jury-package-release-replay-summary` manifest retention/provenance, wrong `package-release-evidence-replay` source job, wrong `retentionDays: 90`, and retained summary content drift from failed and replacement release archive evidence. Use it when the replay summary artifact expired before promotion or when the release record no longer proves summary retention.

## Replay Summary Artifact Expiry Remediation Handoff

Replay summary artifact expiry remediation handoff now documents how to reconstruct `jury-package-release-replay-summary.md` from the retained manifest and `archive-drift-remediation-audit.json` after the 90-day CI artifact expires. The handoff requires a `jury.package_release_replay_summary_expiry_handoff.v1` record with the source artifact, 90-day expiry, failed package version, replacement package version, reconstructed inputs, reconstructed summary path, and reviewing maintainer before the failed or replacement release archive closes. The fixture validator loads [schemas/package-release-replay-summary-expiry-handoff.schema.json](schemas/package-release-replay-summary-expiry-handoff.schema.json) and checks [examples/ci/fixtures/package-release/jury-package-release-replay-summary-expiry-handoff.json](examples/ci/fixtures/package-release/jury-package-release-replay-summary-expiry-handoff.json).

## Replay Summary Expiry Handoff Schema Failure Troubleshooting

Replay summary expiry handoff schema failure troubleshooting now covers validator failures for `jury-package-release-replay-summary-expiry-handoff.json`. It documents local `fixtures:package-release:check` replay, schema-critical field inspection, retained manifest relationship checks for failed and replacement package versions, and maintainer approval checks against `archive-drift-remediation-audit.json` before a failed or replacement release archive closes.

## Bundle Preflight

`bundle preflight --bundle review-bundle.json` validates imported bundles before local state is created or mutated. It reports bundle schema, producer metadata, provenance, record, cross-reference, and trust policy errors so CI consumers can reject third-party artifacts before `bundle import`.

## Trust Policy

Trust policy flags on `bundle preflight` and `bundle import` let CI allow or reject bundles by expected producer name, producer version, source, and revision pattern.

## Signed Attestations

Signed bundle attestations are available through `bundle export --attest-key`, `bundle export --attest-private-key`, `bundle preflight --verify-attestation-key`, `bundle preflight --verify-attestation-public-key`, and the matching `bundle import` verification flags. CI should combine attestation verification with trust policy flags before importing third-party bundles.

## Key Policy Manifests

`bundle preflight --key-policy` and `bundle import --key-policy` load a `jury.key_policy.v1` manifest containing trusted producer metadata and RSA public keys. Use it when CI needs one reviewed file for expected producers, source or revision constraints, key ids, and public keys. Key entries support `valid_from`, `valid_until`, `revoked_at`, and `revoked_reason` so CI can retire expired or compromised producer keys. Policy verification output identifies matching producer entries and every key under those producers, including not-selected, usable, verified, revoked, blocked-by-revocation, outside-validity, read-error, and signature-mismatch statuses.

## Next Hardening Step

Add retained package release evidence manifest archive drift remediation audit record CI replay artifact summary retention failure CI artifact expiry remediation handoff schema failure CI workflow summary diagnostics retention handoff schema failure troubleshooting CI replay enforcement failure troubleshooting remediation audit handoff for failed and replacement release archives.
