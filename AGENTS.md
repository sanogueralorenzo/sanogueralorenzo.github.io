# AGENTS

- Prefer simple, explicit, feature-owned structure; colocate code and tests, keep entry points thin, share only proven common code, and avoid unnecessary cross-project coupling.
- Make the smallest complete change: update affected code, tests, and docs; remove replaced code; avoid unrelated refactors.
- Run focused checks and verify runtime behavior when practical; report gaps.
- Commit and push to `main` unless asked otherwise.
- More specific `AGENTS.md` files override this file within their scope.
