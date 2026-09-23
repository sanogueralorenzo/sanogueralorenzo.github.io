# AGENTS

- Prefer simple, explicit structure with clear ownership; colocate related code and tests when useful, keep entry points thin, share only proven common code, and avoid unnecessary cross-project coupling.
- Before editing a subproject, read and follow its local `AGENTS.md`, if present.
- Make the smallest complete change: update affected code, tests, and docs; remove replaced code; avoid unrelated refactors.
- CI workflows are for the site only; do not add CI for other projects unless the user changes this rule.
- Run focused checks and verify runtime behavior when practical; report gaps.
- Commit and push to `main` unless asked otherwise.
