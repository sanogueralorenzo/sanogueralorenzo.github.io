# AGENTS

## General Rules
- Clarity first.
- Forward-only.
- No legacy/compat/backwards compatible code unless requested.
- Update call sites and tests in the same change.
- Delete replaced code.
- Single source of truth.
- Small, explicit functions.
- No hidden side effects.
- Encapsulate/reuse when it improves clarity.
- Avoid unnecessary abstraction.
- Create packages by feature, not by layer.
- Prefer reactive flows over one-shot patterns.
- For any task that changes code, before the final response: commit and push directly to `main` by default.
- Never create a branch unless explicitly requested.
- If commit/push or install/run cannot be completed, fix the issue and try again.

## Mobile Rules (Android)
- No main-thread blocking.
- Prefer child `NavHost`s over one monolithic `NavHost`.
- Keep presentation as Compose + Mavericks `ViewModel` + Mavericks `State`.
- Use Mavericks `Async` + `execute` with suspend requests.
- Use feature-scoped repositories for storage and network.
- For any task that changes Android app behavior, before the final response: install and launch the app when a device is available.

## Web Rules
- Keep web modules feature-scoped, not layer-scoped.
- Use explicit loading/error/empty states for async data.
- Keep UI state deterministic with a single source of truth per feature.
- Prefer simple, composable components over framework-heavy abstractions.

## Scripting Rules
- Scripts must be non-interactive and repeatable.
- Shell scripts must use `set -euo pipefail`.
- Use clear inputs/flags and fail with non-zero exits on errors.
- Keep script output concise and action-oriented.
