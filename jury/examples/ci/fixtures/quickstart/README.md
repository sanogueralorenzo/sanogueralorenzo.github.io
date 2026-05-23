# Jury Quickstart Fixtures

These fixtures are the expected outputs from the documented quickstart CI flow.

- [verdict.json](verdict.json): accepted `jury.verdict.v1` output.
- [review-bundle.json](review-bundle.json): portable `jury.review_bundle.v1` state.
- [gate.json](gate.json): JSON gate output for the accepted verdict.

They are generated with `JURY_NOW=2026-05-23T00:00:00.000Z` and `claim_ci_change`. The Jury test suite regenerates these artifacts from the quickstart shell block and fails when they drift.
