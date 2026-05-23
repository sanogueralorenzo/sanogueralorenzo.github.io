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
- [scripts/check-package-manifest.mjs](scripts/check-package-manifest.mjs)
- [schemas](schemas)
- [examples/ci/jury-package-manifest-check.yml](examples/ci/jury-package-manifest-check.yml)
- [examples/ci/jury-npm-publish.yml](examples/ci/jury-npm-publish.yml)
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
npm --prefix jury run package:manifest:check
```

The manifest check runs `npm pack --dry-run --json` from the package root, equivalent to `cd jury && npm pack --dry-run --json`, and fails if the tarball would omit `release.json`, the CI adoption guide, any `release.json.ciAdoption.workflows[].path` file, or any required package file above.

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) when CI reports a package manifest failure during release packaging.

## Dry-Run Publication Record

Before npm publication, save the pack dry run output and record the exact package identity that will be published:

```shell
(cd jury && npm pack --dry-run --json) > jury-pack-dry-run.json
node -e "const [pack]=JSON.parse(require('node:fs').readFileSync('jury-pack-dry-run.json','utf8')); console.log(JSON.stringify({packageVersion: pack.version, tarballName: pack.filename}, null, 2));"
```

The release checklist must record both `packageVersion` and `tarballName` before any `npm publish --provenance --access public` step can run. For `@sanogueralorenzo/jury@0.1.0`, the expected tarball name is `sanogueralorenzo-jury-0.1.0.tgz`. If the version or tarball name does not match the intended release, stop before exposing `NODE_AUTH_TOKEN` and use [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Reusable CI Step

Copy [examples/ci/jury-package-manifest-check.yml](examples/ci/jury-package-manifest-check.yml) into `.github/workflows/` and call it before the publication job:

```yaml
jobs:
  jury-package-manifest:
    uses: ./.github/workflows/jury-package-manifest-check.yml
```

[examples/ci/jury-npm-publish.yml](examples/ci/jury-npm-publish.yml) shows the full release shape: `dry-run-publication` has `needs: package-manifest`, uploads `jury-pack-dry-run.json` and `jury-pack-dry-run-record.json` as `jury-package-dry-run`, and keeps that artifact for 30 days with `retention-days: 30`. `publish` downloads and verifies that artifact before the step that maps `secrets.NPM_TOKEN` to `NODE_AUTH_TOKEN`. The workflow requires `dry_run_reviewer`; the verification step writes `packageVersion`, `tarballName`, and `reviewedBy` to `GITHUB_STEP_SUMMARY` so the release page records the package identity and who reviewed it before credentials were exposed. Keep `NODE_AUTH_TOKEN` in `secrets.NPM_TOKEN`.

## Post-Publication Comparison

After publication, compare the retained `jury-package-dry-run` artifact with npm registry metadata before closing the release. Download `jury-pack-dry-run-record.json` from the workflow artifact and run:

```shell
node -e "const fs=require('node:fs'); const record=JSON.parse(fs.readFileSync('jury-pack-dry-run-record.json','utf8')); console.log(JSON.stringify({packageVersion: record.packageVersion, tarballName: record.tarballName}, null, 2));"
npm view @sanogueralorenzo/jury@<packageVersion> version dist.tarball --json
```

The npm `version` must equal `packageVersion`. The npm `dist.tarball` URL must end with the retained `tarballName`. If either value differs, keep the release open and investigate before deleting the retained artifact.

## Rollback After Downstream Verification Failure

If `npm publish --provenance --access public` succeeds but downstream Jury verification later rejects the package, treat the published version as immutable. Do not rerun publication for the same version. Keep `jury-package-dry-run`, `jury-pack-dry-run-record.json`, the `GITHUB_STEP_SUMMARY`, and downstream failure artifacts until the replacement release passes.

Record the failed package identity, mark the release failed, deprecate the bad version when registry policy allows it, and ship a new patch version after fixing the downstream verification issue:

```shell
npm view @sanogueralorenzo/jury@<packageVersion> version dist.tarball --json
npm deprecate @sanogueralorenzo/jury@<packageVersion> "Downstream Jury verification failed; use a later patch release."
```

### Replacement Patch Evidence

Before closing the failed release, prove the replacement patch supersedes the failed publication. Save npm metadata for the replacement and compare it with the retained failed dry-run record:

```shell
npm view @sanogueralorenzo/jury@<replacementPackageVersion> version dist.tarball --json > replacement-npm-view.json
node -e 'const fs=require("node:fs"); const failed=JSON.parse(fs.readFileSync("jury-pack-dry-run-record.json","utf8")); const replacement=JSON.parse(fs.readFileSync("replacement-npm-view.json","utf8")); const replacementTarball=typeof replacement["dist.tarball"]==="string" ? replacement["dist.tarball"] : replacement.dist?.tarball; if (!replacement.version) throw new Error("replacement version missing"); if (!replacementTarball) throw new Error("replacement dist.tarball missing"); if (replacement.version === failed.packageVersion) throw new Error("replacement version must differ from failed packageVersion"); if (replacementTarball.endsWith(failed.tarballName)) throw new Error("replacement tarball must differ from failed tarballName"); console.log(JSON.stringify({failedPackageVersion: failed.packageVersion, failedTarballName: failed.tarballName, replacementPackageVersion: replacement.version, replacementTarball}, null, 2));'
```

Keep that output with the replacement downstream verification pass, the failed-version deprecation result when available, and the retained failed `jury-package-dry-run` artifact. The evidence bundle is complete only when it records the failed `packageVersion`, failed `tarballName`, replacement `packageVersion`, replacement `dist.tarball`, downstream verifier pass, and whether the failed version was deprecated.

## npm Credentials and Provenance

Before enabling publication, create `secrets.NPM_TOKEN` as an npm token limited to publishing `@sanogueralorenzo/jury`. The workflow maps that secret to `NODE_AUTH_TOKEN` only in the final publish step, after `needs: package-manifest` has passed and the downloaded dry-run record has verified. Keep package-manifest and dry-run-publication jobs token-free.

Keep `permissions.id-token: write` and `npm publish --provenance --access public` together so the package is published with GitHub Actions provenance. If provenance is disabled or the id-token permission is removed, treat that as a release-blocking change and review it before publishing.

## Failure Examples

If the tarball omits the CI adoption guide, the check exits non-zero and reports the missing contract path:

```json
{
  "ok": false,
  "missing": ["CI_ADOPTION.md"]
}
```

If the tarball omits a supported workflow, the missing workflow path is reported directly:

```json
{
  "ok": false,
  "missing": ["examples/ci/jury-trusted-bundle-verify.yml"]
}
```

Use `node jury/scripts/check-package-manifest.mjs --pack-manifest <npm-pack-json>` to replay a saved `npm pack --dry-run --json` manifest while debugging package file omissions.
