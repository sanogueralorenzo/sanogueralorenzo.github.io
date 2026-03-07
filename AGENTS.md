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

## Git and Delivery Rules
- Default workflow: for any task that changes code, before the final response, commit and push directly to `main`.
- Do not create a branch unless explicitly requested, or unless the task explicitly requires a branch/PR workflow.
- If branch/PR workflow is required, use:
  - Branch: `<workspace_branch_prefix>/<TICKET-KEY>_<short_summary>` (lowercase, underscores, 2 words).
  - PR title: `<TICKET-KEY> <Title>`.
  - First non-empty PR description line: `<TICKET-KEY>`.
  - Preserve template content and return the PR link.
- If commit/push/install/run fails, attempt to fix and retry.
- If blocked by auth, permissions, branch protection, or network after retries: report the exact command and error, then stop.

## Tooling and Ticket Rules
- Use official CLIs by default: `gh` for GitHub, `acli` for Jira, unless explicitly told otherwise.
- Jira descriptions/comments must use ADF JSON via `--description-file` / `--body-file`.
- For `gh` / `acli` / Slack actions, return direct links for created, updated, or referenced items.
- If CLI install or auth fails, report the exact error and stop before API/web fallback.

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
- Shell scripts must use `set -euo pipefail` and a shell that supports it (for example `bash`).
- Use clear inputs/flags and fail with non-zero exits on errors.
- Keep script output concise and action-oriented.
