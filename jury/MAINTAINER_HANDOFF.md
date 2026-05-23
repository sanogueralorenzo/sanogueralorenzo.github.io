# Jury Maintainer Handoff

Jury v1 adoption is currently centered on a clean-checkout CI path that produces a verdict, gate result, and portable review bundle without external dependencies.

## Adoption Artifacts

- [QUICKSTART.md](QUICKSTART.md): local clean-checkout command sequence.
- [examples/ci/jury-review-gate.yml](examples/ci/jury-review-gate.yml): copyable GitHub Actions workflow.
- [examples/ci/fixtures/quickstart](examples/ci/fixtures/quickstart): expected `verdict.json`, `gate.json`, and `review-bundle.json` outputs.
- [MIGRATION.md](MIGRATION.md): artifact handoff and bundle replay path.
- [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md): release-readiness checklist.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md): failure-mode inspection and retry/reject examples.

## Validation

Run these from the repository root before handing Jury to another maintainer:

```shell
npm --prefix jury test
npm --prefix jury run check -- --state-dir /tmp/jury-maintainer-handoff --json
```

The test suite covers the quickstart, GitHub Actions workflow commands, fixture synchronization, troubleshooting failure examples, release checklist links, and this handoff note's references.

## Current Hardening Step

`bundle preflight --bundle review-bundle.json` validates imported bundles before local state is created or mutated. It reports bundle schema, producer metadata, provenance, record, and cross-reference errors so CI consumers can reject third-party artifacts before `bundle import`.

## Next Hardening Step

Add trust policy checks for `review-bundle.json` producers so CI can allow or reject bundles by expected producer name, version, source, and revision pattern.
