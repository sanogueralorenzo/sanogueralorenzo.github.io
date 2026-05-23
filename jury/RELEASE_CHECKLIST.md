# Jury Release Readiness

Use this checklist before treating the Jury prototype as a reusable v1 adoption path.

## Adoption Path

- [ ] Run [QUICKSTART.md](QUICKSTART.md) from a clean checkout.
- [ ] Choose a workflow path with [CI_ADOPTION.md](CI_ADOPTION.md).
- [ ] Verify [release.json](release.json) lists the selected `ciAdoption` workflow variant.
- [ ] Review [PUBLISHING.md](PUBLISHING.md) before changing package publication settings.
- [ ] Copy [examples/ci/jury-package-manifest-check.yml](examples/ci/jury-package-manifest-check.yml) into `.github/workflows/` before publication CI.
- [ ] Use [examples/ci/jury-npm-publish.yml](examples/ci/jury-npm-publish.yml) as the npm publication shape when releases need `needs: package-manifest`.
- [ ] Confirm publication CI runs `package-release-fixtures` with `npm --prefix "$JURY_PACKAGE_DIR" run fixtures:package-release:check` before `dry-run-publication`.
- [ ] Confirm publication CI runs `npm --prefix "$JURY_PACKAGE_DIR" run fixtures:package-release:drift` before `dry-run-publication`.
- [ ] Upload `rollback-audit.json`, `replacement-patch-audit.json`, and `archive-drift-remediation-audit.json` as the `jury-package-release-evidence` CI artifact for package release audit comparison.
- [ ] Export `retained-package-release-evidence-manifest.json` in publication CI and upload it as the `jury-package-release-archive-manifest` CI artifact.
- [ ] Download `jury-package-release-evidence` and replay it with `npm --prefix jury run fixtures:package-release:check -- --fixture-dir <downloaded-artifact-dir>` before `dry-run-publication`.
- [ ] Download `jury-package-release-archive-manifest` and verify it with `--verify-manifest "$JURY_PACKAGE_RELEASE_MANIFEST_PATH"` before `dry-run-publication`.
- [ ] Review the `package-release-evidence-replay` `GITHUB_STEP_SUMMARY` for failed package version, failed tarball name, replacement package version, failed archive evidence, replacement archive evidence, and remediation approver before `dry-run-publication`.
- [ ] Confirm `package-release-evidence-replay` uploads `jury-package-release-replay-summary` with `jury-package-release-replay-summary.md` and `retention-days: 90`.
- [ ] If package release evidence replay fails, use [TROUBLESHOOTING.md](TROUBLESHOOTING.md) to check `JURY_PACKAGE_RELEASE_EVIDENCE_DIR`, missing artifact files, and rollback/replacement audit schema errors before `dry-run-publication`.
- [ ] Run `(cd jury && npm pack --dry-run --json) > jury-pack-dry-run.json` after the package manifest check.
- [ ] Record the dry-run package version from `jury-pack-dry-run.json` as `packageVersion`.
- [ ] Record the dry-run tarball name from `jury-pack-dry-run.json` as `tarballName`, for example `sanogueralorenzo-jury-0.1.0.tgz`.
- [ ] Upload `jury-pack-dry-run.json` and `jury-pack-dry-run-record.json` as the `jury-package-dry-run` CI artifact.
- [ ] Keep `jury-package-dry-run` and `jury-package-release-evidence` CI artifacts for 90 days with `retention-days: 90`.
- [ ] Download and verify the `jury-package-dry-run` artifact before any step maps `secrets.NPM_TOKEN` to `NODE_AUTH_TOKEN`.
- [ ] Set `dry_run_reviewer` to the person who reviewed the verified package summary.
- [ ] Review the `GITHUB_STEP_SUMMARY` entry for the verified `packageVersion`, `tarballName`, and `reviewedBy`.
- [ ] Confirm `tarballName` matches the recorded `packageVersion` before `npm publish --provenance --access public`.
- [ ] After publication, compare retained `jury-pack-dry-run-record.json` with `npm view @sanogueralorenzo/jury@<packageVersion> version dist.tarball --json`.
- [ ] If downstream verification fails after publication, keep retained dry-run artifacts, mark the version failed, and ship a later patch version instead of republishing the same version.
- [ ] For replacement patches after failed publication, record the failed `packageVersion`, failed `tarballName`, replacement `packageVersion`, replacement `dist.tarball`, replacement downstream verification pass, and failed-version deprecation result when available.
- [ ] Promote failed and replacement release evidence from temporary CI artifacts into the release record or incident archive before the 90-day artifact expiry.
- [ ] Promote `jury-package-release-replay-summary.md` from `jury-package-release-replay-summary` with the failed and replacement release archive evidence before the 90-day artifact expiry.
- [ ] Record retained artifact provenance for `jury-package-dry-run`, `jury-package-release-evidence`, and `jury-package-release-replay-summary`: source workflow, run id, source revision, source job, `retentionDays`, and uploaded file list.
- [ ] Confirm retained failed and replacement evidence comes from the same `jury-npm-publish.yml` workflow run and source revision before closing the release.
- [ ] Export `retained-package-release-evidence-manifest.json` with `npm --prefix jury run fixtures:package-release:check -- --fixture-dir <retained-evidence-dir> --manifest-out retained-package-release-evidence-manifest.json`.
- [ ] Confirm the retained archive manifest validates against [schemas/package-release-archive-manifest.schema.json](schemas/package-release-archive-manifest.schema.json).
- [ ] Verify `retained-package-release-evidence-manifest.json` with `npm --prefix jury run fixtures:package-release:check -- --fixture-dir <retained-evidence-dir> --verify-manifest retained-package-release-evidence-manifest.json`.
- [ ] Run `npm --prefix jury run fixtures:package-release:drift` before release to confirm the checked-in retained archive manifest has not drifted from failed or replacement archive evidence or archive evidence digests.
- [ ] If retained archive drift appears, restore the failed or replacement archive evidence first, regenerate the manifest from the restored evidence directory, review the diff, and record the approving maintainer before replacing the archived copy.
- [ ] Store `archive-drift-remediation-audit.json` with failed-publication drift, replacement-patch drift, restored evidence, verification commands, and approving maintainer when replacing an archived manifest after drift.
- [ ] If retained package release manifest replay fails, use [TROUBLESHOOTING.md](TROUBLESHOOTING.md) to inspect manifest identity, required archive evidence, retention artifacts, and provenance artifacts.
- [ ] Retain promoted failed and replacement release evidence until at least 180 days after replacement downstream verification passes.
- [ ] Use [TROUBLESHOOTING.md](TROUBLESHOOTING.md) when the dry-run artifact is stale or mismatched.
- [ ] Store the npm publish token as `secrets.NPM_TOKEN` with scope limited to publishing `@sanogueralorenzo/jury`.
- [ ] Expose `NODE_AUTH_TOKEN` only in the publish job after `needs: package-manifest` passes and the dry-run artifact verifies.
- [ ] Keep `permissions.id-token: write` and `npm publish --provenance --access public` enabled for npm provenance.
- [ ] Copy [examples/ci/jury-review-gate.yml](examples/ci/jury-review-gate.yml) into `.github/workflows/`.
- [ ] Copy [examples/ci/jury-signed-review-gate.yml](examples/ci/jury-signed-review-gate.yml) when the producer must sign `review-bundle.signed.json` with `secrets.JURY_CI_PRIVATE_KEY`.
- [ ] Copy [examples/ci/jury-signed-artifact-handoff.yml](examples/ci/jury-signed-artifact-handoff.yml) when producer and consumer CI jobs need an artifact download handoff.
- [ ] Copy [examples/ci/jury-trusted-bundle-verify.yml](examples/ci/jury-trusted-bundle-verify.yml) into `.github/workflows/` for downstream trusted-producer verification.
- [ ] Compare generated outputs with [examples/ci/fixtures/quickstart](examples/ci/fixtures/quickstart).
- [ ] Verify signed bundle handoff with [examples/ci/fixtures/key-policy](examples/ci/fixtures/key-policy).
- [ ] Review [examples/ci/fixtures/key-policy-rotation](examples/ci/fixtures/key-policy-rotation) before rotating producer signing keys.
- [ ] Compare package publication rollback evidence with [examples/ci/fixtures/package-release](examples/ci/fixtures/package-release).
- [ ] `npm --prefix jury run fixtures:key-policy:check` passes before release.
- [ ] `npm --prefix jury run fixtures:package-release:check` passes before release.
- [ ] Follow [MIGRATION.md](MIGRATION.md) when handing artifacts between jobs.
- [ ] Use [TROUBLESHOOTING.md](TROUBLESHOOTING.md) when CI emits `reject`, `retry`, `human_decision`, or a package manifest failure.
- [ ] Read [MAINTAINER_HANDOFF.md](MAINTAINER_HANDOFF.md) before transferring ownership.

## Required Artifacts

- [ ] `verdict.json` exists and has `schema_version: jury.verdict.v1`.
- [ ] `review-bundle.json` exists and has `schema_version: jury.review_bundle.v1`.
- [ ] `review-bundle.json` includes `producer` and `provenance` with a source revision.
- [ ] `gate.json` exists and has `ok: true`.
- [ ] `node jury/bin/jury.mjs bundle preflight --bundle review-bundle.json` passes before import.
- [ ] `bundle preflight` uses producer trust policy flags before importing third-party bundles.
- [ ] Internal shared-secret bundles are signed with `--attest-key` and verified with `--verify-attestation-key`.
- [ ] Third-party or cross-job producers are signed with `--attest-private-key` and verified with `--verify-attestation-public-key`.
- [ ] CI private signing keys stay in secrets and are written only to runner temp paths during producer jobs.
- [ ] CI consumers use `--key-policy jury-key-policy.json` when producer trust and public keys need to be reviewed as one manifest.
- [ ] Key policy entries include `valid_from`/`valid_until` for rotation windows or `revoked_at`/`revoked_reason` for retired keys.
- [ ] Key-policy preflight output is reviewed when debugging producer/key selection, especially `key_policy.matching_producers` and `key_policy.considered_keys`.
- [ ] `.jury/*.jsonl` exists when raw append-only audit state is needed.

Expected fixture files:

- [examples/ci/fixtures/quickstart/verdict.json](examples/ci/fixtures/quickstart/verdict.json)
- [examples/ci/fixtures/quickstart/review-bundle.json](examples/ci/fixtures/quickstart/review-bundle.json)
- [examples/ci/fixtures/quickstart/gate.json](examples/ci/fixtures/quickstart/gate.json)
- [examples/ci/fixtures/key-policy/jury-key-policy.json](examples/ci/fixtures/key-policy/jury-key-policy.json)
- [examples/ci/fixtures/key-policy/jury-key-policy.untrusted-producer.json](examples/ci/fixtures/key-policy/jury-key-policy.untrusted-producer.json)
- [examples/ci/fixtures/key-policy/ci-public.pem](examples/ci/fixtures/key-policy/ci-public.pem)
- [examples/ci/fixtures/key-policy/review-bundle.signed.json](examples/ci/fixtures/key-policy/review-bundle.signed.json)
- [examples/ci/fixtures/key-policy/README.md](examples/ci/fixtures/key-policy/README.md)
- [examples/ci/fixtures/key-policy-rotation/jury-key-policy.rotation.json](examples/ci/fixtures/key-policy-rotation/jury-key-policy.rotation.json)
- [examples/ci/fixtures/key-policy-rotation/jury-key-policy.revoked-old.json](examples/ci/fixtures/key-policy-rotation/jury-key-policy.revoked-old.json)
- [examples/ci/fixtures/key-policy-rotation/ci-old-public.pem](examples/ci/fixtures/key-policy-rotation/ci-old-public.pem)
- [examples/ci/fixtures/key-policy-rotation/ci-new-public.pem](examples/ci/fixtures/key-policy-rotation/ci-new-public.pem)
- [examples/ci/fixtures/key-policy-rotation/review-bundle.old.signed.json](examples/ci/fixtures/key-policy-rotation/review-bundle.old.signed.json)
- [examples/ci/fixtures/key-policy-rotation/review-bundle.new.signed.json](examples/ci/fixtures/key-policy-rotation/review-bundle.new.signed.json)
- [examples/ci/fixtures/key-policy-rotation/README.md](examples/ci/fixtures/key-policy-rotation/README.md)
- [examples/ci/fixtures/package-release/README.md](examples/ci/fixtures/package-release/README.md)
- [examples/ci/fixtures/package-release/archive-drift-remediation-audit.json](examples/ci/fixtures/package-release/archive-drift-remediation-audit.json)
- [examples/ci/fixtures/package-release/jury-pack-dry-run-record.json](examples/ci/fixtures/package-release/jury-pack-dry-run-record.json)
- [examples/ci/fixtures/package-release/failed-npm-view.json](examples/ci/fixtures/package-release/failed-npm-view.json)
- [examples/ci/fixtures/package-release/downstream-failure-gate.json](examples/ci/fixtures/package-release/downstream-failure-gate.json)
- [examples/ci/fixtures/package-release/rollback-audit.json](examples/ci/fixtures/package-release/rollback-audit.json)
- [examples/ci/fixtures/package-release/replacement-npm-view.json](examples/ci/fixtures/package-release/replacement-npm-view.json)
- [examples/ci/fixtures/package-release/replacement-downstream-gate.json](examples/ci/fixtures/package-release/replacement-downstream-gate.json)
- [examples/ci/fixtures/package-release/replacement-patch-audit.json](examples/ci/fixtures/package-release/replacement-patch-audit.json)
- [examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json](examples/ci/fixtures/package-release/retained-package-release-evidence-manifest.json)
- [schemas/package-release-archive-manifest.schema.json](schemas/package-release-archive-manifest.schema.json)
- [schemas/package-release-evidence.schema.json](schemas/package-release-evidence.schema.json)
- [schemas/package-release-remediation-audit.schema.json](schemas/package-release-remediation-audit.schema.json)
- [scripts/validate-package-release-fixtures.mjs](scripts/validate-package-release-fixtures.mjs)

## Validation

```shell
npm --prefix jury test
npm --prefix jury run check -- --state-dir /tmp/jury-release-readiness --json
npm --prefix jury run package:manifest:check
npm --prefix jury run fixtures:package-release:check
npm --prefix jury run fixtures:package-release:drift
```

The release is ready when the quickstart, workflow, fixture sync tests, migration path, tarball manifest check, and strict check all pass against the same artifact contract.
