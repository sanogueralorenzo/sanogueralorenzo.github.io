# AGENTS

- Prefer simple, direct solutions. Optimize for clarity, not cleverness.
- Inspect the relevant code before changing it; do not guess at behavior.
- Make the smallest complete change. Update affected call sites, tests, and docs, and remove replaced code.
- Avoid speculative abstractions, compatibility layers, and unrelated refactors.
- Keep state, control flow, side effects, and failure handling explicit.
- Preserve unrelated work. Never commit secrets, generated artifacts, or local environment files.
- Run the narrowest relevant checks and verify runnable behavior when practical. Report anything not verified.
- After validation, commit and push to `main` unless the user requests another workflow.
- More specific `AGENTS.md` files override this file within their scope.
