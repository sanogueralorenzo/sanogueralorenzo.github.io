# Jury Export Examples

These files are stable v1 examples for systems that want to consume Jury output without reading local `.jury/` state directly.

- `check.passed.v1.json`: a completed required verifier check.
- `verdict.accept.v1.json`: an accepted verdict that references the check.

Consumers should treat `schema_version` as the compatibility key and reject unknown major versions.
