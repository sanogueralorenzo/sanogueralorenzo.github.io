# Jury Release Readiness

Use this checklist before treating the Jury prototype as a reusable v1 adoption path.

## Adoption Path

- [ ] Run [QUICKSTART.md](QUICKSTART.md) from a clean checkout.
- [ ] Copy [examples/ci/jury-review-gate.yml](examples/ci/jury-review-gate.yml) into `.github/workflows/`.
- [ ] Compare generated outputs with [examples/ci/fixtures/quickstart](examples/ci/fixtures/quickstart).
- [ ] Follow [MIGRATION.md](MIGRATION.md) when handing artifacts between jobs.
- [ ] Use [TROUBLESHOOTING.md](TROUBLESHOOTING.md) when CI emits `reject`, `retry`, or `human_decision`.
- [ ] Read [MAINTAINER_HANDOFF.md](MAINTAINER_HANDOFF.md) before transferring ownership.

## Required Artifacts

- [ ] `verdict.json` exists and has `schema_version: jury.verdict.v1`.
- [ ] `review-bundle.json` exists and has `schema_version: jury.review_bundle.v1`.
- [ ] `review-bundle.json` includes `producer` and `provenance` with a source revision.
- [ ] `gate.json` exists and has `ok: true`.
- [ ] `node jury/bin/jury.mjs bundle preflight --bundle review-bundle.json` passes before import.
- [ ] `bundle preflight` uses producer trust policy flags before importing third-party bundles.
- [ ] Third-party bundles are signed with `--attest-key` and verified with `--verify-attestation-key`.
- [ ] `.jury/*.jsonl` exists when raw append-only audit state is needed.

Expected fixture files:

- [examples/ci/fixtures/quickstart/verdict.json](examples/ci/fixtures/quickstart/verdict.json)
- [examples/ci/fixtures/quickstart/review-bundle.json](examples/ci/fixtures/quickstart/review-bundle.json)
- [examples/ci/fixtures/quickstart/gate.json](examples/ci/fixtures/quickstart/gate.json)

## Validation

```shell
npm --prefix jury test
npm --prefix jury run check -- --state-dir /tmp/jury-release-readiness --json
```

The release is ready when the quickstart, workflow, fixture sync tests, migration path, and strict check all pass against the same artifact contract.
