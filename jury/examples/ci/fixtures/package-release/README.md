# Package Release Evidence Fixtures

These fixtures show the evidence bundle maintainers should keep when npm accepts a Jury package but downstream verification rejects it.

## Rollback Audit

[rollback-audit.json](rollback-audit.json) records the immutable failed publication. It points to:

- [jury-pack-dry-run-record.json](jury-pack-dry-run-record.json): the retained dry-run package identity.
- [failed-npm-view.json](failed-npm-view.json): registry metadata for the failed published package.
- [downstream-failure-gate.json](downstream-failure-gate.json): the downstream Jury rejection.

The failed version is not republished. The audit records the deprecation command and requires a later replacement patch audit before the incident closes.

## Replacement Patch Audit

[replacement-patch-audit.json](replacement-patch-audit.json) proves the replacement patch supersedes the failed publication. It points to:

- [replacement-npm-view.json](replacement-npm-view.json): registry metadata for the later patch version.
- [replacement-downstream-gate.json](replacement-downstream-gate.json): the downstream Jury acceptance for the replacement.

The replacement evidence is complete only when the replacement `packageVersion` differs from the failed `packageVersion`, the replacement `dist.tarball` does not end with the failed `tarballName`, downstream verification passes, and the failed-version deprecation result is recorded when available.

## Retention Policy

Both audit files include `retention.policy: jury.package_release_retention.v1`. The policy requires maintainers to promote temporary `jury-package-dry-run`, `jury-package-release-evidence`, and `jury-package-release-replay-summary` CI artifacts into the release record or incident archive before the 90-day artifact expiry.

Both audit files also include `retention.provenance` for the retained CI artifacts. Provenance records the GitHub Actions source, `jury-npm-publish.yml` workflow, run id, source revision, source job, `retentionDays: 90`, and uploaded file list for `jury-package-dry-run`, `jury-package-release-evidence`, and `jury-package-release-replay-summary`.

Retain the failed and replacement evidence until at least 180 days after replacement downstream verification passes. The replacement audit depends on the failed `packageVersion`, failed `tarballName`, failed downstream gate, rollback audit, replacement npm metadata, replacement downstream gate, and failed-version deprecation result.

## Release Archive Manifest

[retained-package-release-evidence-manifest.json](retained-package-release-evidence-manifest.json) is the retained release archive handoff fixture. It combines the failed publication identity, replacement patch identity, retention policy, CI artifact provenance, and SHA-256 digests for retained failed and replacement archive evidence that must travel with the release record or incident archive, including [jury-package-release-replay-summary.md](jury-package-release-replay-summary.md).

## Archive Drift Remediation Audit

[archive-drift-remediation-audit.json](archive-drift-remediation-audit.json) is the retained remediation audit fixture for archive drift. It records which failed publication and replacement patch evidence drifted, which archived files were restored before manifest regeneration, the verification commands that proved the repaired archive, and the maintainer approval that must be recorded before replacing an archived manifest.

## Replay Summary Expiry Handoff

[jury-package-release-replay-summary-expiry-handoff.json](jury-package-release-replay-summary-expiry-handoff.json) is the reviewed handoff fixture for a missing `jury-package-release-replay-summary` CI artifact after the 90-day expiry. It records the reconstructed summary path, retained inputs, failed package version, replacement package version, and reviewing maintainer.

If the handoff schema fails, use [../../../../TROUBLESHOOTING.md](../../../../TROUBLESHOOTING.md) to inspect the required schema version, expiry reason, source artifact, 90-day expiry, reconstructed summary path, reconstructed inputs, failed and replacement package versions, and reviewing maintainer before closing the failed or replacement release archive.

## Replay Summary Diagnostics

[jury-package-release-replay-summary-diagnostics.json](jury-package-release-replay-summary-diagnostics.json) is the CI workflow summary diagnostics fixture. It records the replay source job, summary artifact, failed package identity, replacement package identity, retained archive evidence lists, remediation approver, and checked summary lines that must match [jury-package-release-replay-summary.md](jury-package-release-replay-summary.md).

## Replay Summary Diagnostics Retention Handoff

[jury-package-release-replay-summary-diagnostics-retention-handoff.json](jury-package-release-replay-summary-diagnostics-retention-handoff.json) is the reviewed handoff fixture for retaining `jury-package-release-replay-summary-diagnostics.json` with failed and replacement release archives. It records the replay source artifact, source job, 90-day retention window, diagnostics schema version, retained diagnostics file, summary file, retained companion records, failed package version, failed tarball name, replacement package version, workflow run id, source revision, and reviewing maintainer.

The publication workflow regenerates this handoff during `package-release-evidence-replay`, then replays the generated file against the retained manifest, diagnostics JSON, retained fixture handoff, archive drift remediation audit, and replay summary artifact provenance before uploading the replay summary artifact.

If the diagnostics retention handoff schema fails, use [../../../../TROUBLESHOOTING.md](../../../../TROUBLESHOOTING.md) to inspect the required schema version, source artifact, source job, retention window, diagnostics schema version, retained companion records, failed and replacement package identity, workflow run id, source revision, and reviewing maintainer before closing the failed or replacement release archive.

## Validation

Run the fixture check after changing these files:

```shell
npm --prefix jury run fixtures:package-release:check
npm --prefix jury run fixtures:package-release:check -- --manifest-out examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json
npm --prefix jury run fixtures:package-release:check -- --verify-manifest examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json
npm --prefix jury run fixtures:package-release:drift
```

The command validates `rollback-audit.json` and `replacement-patch-audit.json` against [../../../../schemas/package-release-evidence.schema.json](../../../../schemas/package-release-evidence.schema.json), validates `archive-drift-remediation-audit.json` against [../../../../schemas/package-release-remediation-audit.schema.json](../../../../schemas/package-release-remediation-audit.schema.json), validates `jury-package-release-replay-summary-diagnostics.json` against [../../../../schemas/package-release-replay-summary-diagnostics.schema.json](../../../../schemas/package-release-replay-summary-diagnostics.schema.json), validates `jury-package-release-replay-summary-diagnostics-retention-handoff.json` against [../../../../schemas/package-release-replay-summary-diagnostics-retention-handoff.schema.json](../../../../schemas/package-release-replay-summary-diagnostics-retention-handoff.schema.json), validates `jury-package-release-replay-summary-expiry-handoff.json` against [../../../../schemas/package-release-replay-summary-expiry-handoff.schema.json](../../../../schemas/package-release-replay-summary-expiry-handoff.schema.json), then checks the fixture relationships that prove the replacement patch supersedes the failed publication and remediation is approved before archived manifest replacement. `--manifest-out` writes a `jury.package_release_archive_manifest.v1` file for the retained release archive, validates it against [../../../../schemas/package-release-archive-manifest.schema.json](../../../../schemas/package-release-archive-manifest.schema.json), and combines failed publication evidence, replacement patch evidence, retention requirements, artifact provenance, and archive evidence digests into one handoff manifest. `--verify-manifest` validates an archived manifest against the same schema and compares it with the current retained evidence before maintainers close the failed release record. `fixtures:package-release:drift` runs the same comparison against the checked-in retained release archive manifest so fixture changes fail when the manifest drifts from the failed or replacement release archive evidence. If manifest replay or drift checking fails, use [../../../../TROUBLESHOOTING.md](../../../../TROUBLESHOOTING.md) to inspect the manifest identity, required archive evidence, retention artifacts, provenance artifacts, archive evidence digests, and remediation audit record.
