# Jury Package Publication Notes

Jury is still marked `private: true` in [package.json](package.json), so these notes describe the package contract to preserve before any future registry publication.

## CI Adoption Metadata Contract

[release.json](release.json) is the machine-readable entry point for consumers that need Jury CI adoption metadata. The `ciAdoption` block must keep:

- `guide`: the path to [CI_ADOPTION.md](CI_ADOPTION.md).
- `workflows`: one entry per supported workflow variant.
- `workflows[].path`: the copyable GitHub Actions workflow path.
- `workflows[].trustBoundary`: the trust boundary that decides when to use the variant.
- `workflows[].artifacts`: the uploaded artifacts or reusable workflow defaults a consumer should expect.

Publication tooling should consume `release.json` instead of parsing Markdown tables. Markdown guides are for humans; `release.json` is the package contract.

## Required Package Files

The package must include these files before the package becomes publishable:

- [package.json](package.json)
- [PUBLISHING.md](PUBLISHING.md)
- [release.json](release.json)
- [CI_ADOPTION.md](CI_ADOPTION.md)
- [MIGRATION.md](MIGRATION.md)
- [README.md](README.md)
- [bin/jury.mjs](bin/jury.mjs)
- [schemas](schemas)
- [examples/ci/jury-review-gate.yml](examples/ci/jury-review-gate.yml)
- [examples/ci/jury-signed-review-gate.yml](examples/ci/jury-signed-review-gate.yml)
- [examples/ci/jury-signed-artifact-handoff.yml](examples/ci/jury-signed-artifact-handoff.yml)
- [examples/ci/jury-trusted-bundle-verify.yml](examples/ci/jury-trusted-bundle-verify.yml)
- [examples/ci/fixtures/key-policy](examples/ci/fixtures/key-policy)

## Pre-Publication Check

Run these commands before removing `private: true` or publishing a package tarball:

```shell
npm --prefix jury test
npm --prefix jury run check -- --state-dir /tmp/jury-package-publication --json
cd jury && npm pack --dry-run --json
```

Review the dry-run file list and confirm every `release.json.ciAdoption.workflows[].path` file and every required package file above is present.
