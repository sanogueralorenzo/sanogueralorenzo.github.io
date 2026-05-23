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

Both audit files include `retention.policy: jury.package_release_retention.v1`. The policy requires maintainers to promote temporary `jury-package-dry-run` and `jury-package-release-evidence` CI artifacts into the release record or incident archive before the 90-day artifact expiry.

Retain the failed and replacement evidence until at least 180 days after replacement downstream verification passes. The replacement audit depends on the failed `packageVersion`, failed `tarballName`, failed downstream gate, rollback audit, replacement npm metadata, replacement downstream gate, and failed-version deprecation result.

## Validation

Run the fixture check after changing these files:

```shell
npm --prefix jury run fixtures:package-release:check
```

The command validates `rollback-audit.json` and `replacement-patch-audit.json` against [../../../../schemas/package-release-evidence.schema.json](../../../../schemas/package-release-evidence.schema.json), then checks the fixture relationships that prove the replacement patch supersedes the failed publication.
