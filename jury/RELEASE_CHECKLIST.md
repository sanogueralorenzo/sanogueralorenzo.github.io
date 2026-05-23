# Jury Release Readiness

Use this checklist before treating the Jury prototype as a reusable v1 adoption path.

## Adoption Path

- [ ] Run [QUICKSTART.md](QUICKSTART.md) from a clean checkout.
- [ ] Copy [examples/ci/jury-review-gate.yml](examples/ci/jury-review-gate.yml) into `.github/workflows/`.
- [ ] Compare generated outputs with [examples/ci/fixtures/quickstart](examples/ci/fixtures/quickstart).
- [ ] Follow [MIGRATION.md](MIGRATION.md) when handing artifacts between jobs.
- [ ] Use [TROUBLESHOOTING.md](TROUBLESHOOTING.md) when CI emits `reject`, `retry`, or `human_decision`.

## Required Artifacts

- [ ] `verdict.json` exists and has `schema_version: jury.verdict.v1`.
- [ ] `review-bundle.json` exists and has `schema_version: jury.review_bundle.v1`.
- [ ] `gate.json` exists and has `ok: true`.
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
