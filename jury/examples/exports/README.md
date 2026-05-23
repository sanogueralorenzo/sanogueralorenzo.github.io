# Jury Export Examples

These files are stable v1 examples for systems that want to consume Jury output without reading local `.jury/` state directly.

- `check.passed.v1.json`: a completed required verifier check.
- `verdict.accept.v1.json`: an accepted verdict that references the check.
- `review-bundle.accept.v1.json`: a portable bundle containing the claim, check, evidence, and verdict needed to recreate a CI gate result.

Consumers should treat `schema_version` as the compatibility key and reject unknown major versions.
