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

## Next Hardening Step

Add deterministic schema validation for imported `review-bundle.json` files before they are appended into local state. The current bundle import path validates records as they are written, but a preflight command that reports all bundle errors without mutating `.jury/` would make CI adoption safer for third-party producers and easier to debug.
