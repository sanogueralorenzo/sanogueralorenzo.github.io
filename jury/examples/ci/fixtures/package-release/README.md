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
