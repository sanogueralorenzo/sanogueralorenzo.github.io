# Jury Release Readiness

Use this checklist before treating the Jury prototype as a reusable v1 adoption path.

## Adoption Path

- [ ] Run [QUICKSTART.md](QUICKSTART.md) from a clean checkout.
- [ ] Choose a workflow path with [CI_ADOPTION.md](CI_ADOPTION.md).
- [ ] Verify [release.json](release.json) lists the selected `ciAdoption` workflow variant.
- [ ] Review [PUBLISHING.md](PUBLISHING.md) before changing package publication settings.
- [ ] Copy [examples/ci/jury-package-manifest-check.yml](examples/ci/jury-package-manifest-check.yml) into `.github/workflows/` before publication CI.
- [ ] Use [examples/ci/jury-npm-publish.yml](examples/ci/jury-npm-publish.yml) as the npm publication shape when releases need `needs: package-manifest`.
- [ ] Run `(cd jury && npm pack --dry-run --json) > jury-pack-dry-run.json` after the package manifest check.
- [ ] Record the dry-run package version from `jury-pack-dry-run.json` as `packageVersion`.
- [ ] Record the dry-run tarball name from `jury-pack-dry-run.json` as `tarballName`, for example `sanogueralorenzo-jury-0.1.0.tgz`.
- [ ] Upload `jury-pack-dry-run.json` and `jury-pack-dry-run-record.json` as the `jury-package-dry-run` CI artifact.
- [ ] Keep the `jury-package-dry-run` artifact for 30 days with `retention-days: 30`.
- [ ] Download and verify the `jury-package-dry-run` artifact before any step maps `secrets.NPM_TOKEN` to `NODE_AUTH_TOKEN`.
- [ ] Set `dry_run_reviewer` to the person who reviewed the verified package summary.
- [ ] Review the `GITHUB_STEP_SUMMARY` entry for the verified `packageVersion`, `tarballName`, and `reviewedBy`.
- [ ] Confirm `tarballName` matches the recorded `packageVersion` before `npm publish --provenance --access public`.
- [ ] After publication, compare retained `jury-pack-dry-run-record.json` with `npm view @sanogueralorenzo/jury@<packageVersion> version dist.tarball --json`.
- [ ] If downstream verification fails after publication, keep retained dry-run artifacts, mark the version failed, and ship a later patch version instead of republishing the same version.
- [ ] For replacement patches after failed publication, record the failed `packageVersion`, failed `tarballName`, replacement `packageVersion`, replacement `dist.tarball`, replacement downstream verification pass, and failed-version deprecation result when available.
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
- [ ] `npm --prefix jury run fixtures:key-policy:check` passes before release.
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

## Validation

```shell
npm --prefix jury test
npm --prefix jury run check -- --state-dir /tmp/jury-release-readiness --json
npm --prefix jury run package:manifest:check
```

The release is ready when the quickstart, workflow, fixture sync tests, migration path, tarball manifest check, and strict check all pass against the same artifact contract.
