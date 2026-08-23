# AGENTS

- Prefer simple, explicit structure with clear ownership; colocate related code and tests when useful, keep entry points thin, share only proven common code, and avoid unnecessary cross-project coupling.
- Before editing a subproject, read and follow its local `AGENTS.md`, if present.
- Make the smallest complete change: update affected code, tests, and docs; remove replaced code; avoid unrelated refactors.
- Run focused checks and verify runtime behavior when practical; report gaps.
- Commit and push to `main` unless asked otherwise.
