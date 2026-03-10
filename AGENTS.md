# AGENTS

## Rule Format
- INFO | Use `<level> | <instruction>`.
- INFO | Precedence remains `task-specific > scope-specific > global`.

## Global
- MUST | Clarity first; prefer explicit code over clever code.
- MUST | Forward-only changes; no legacy/back-compat code unless requested.
- MUST | Update call sites and tests in the same change.
- MUST | Delete replaced code; keep one source of truth.
- MUST | Keep functions small, explicit, and side-effect aware.
- MUST | Encapsulate/reuse only when it improves clarity.
- MUST_NOT | Add unnecessary abstraction or layer-oriented packaging.
- MUST | Use feature-scoped modules.
- MUST | Use reactive/streaming flows over one-shot patterns when state is ongoing.
- MUST | Use explicit loading/error/empty states for async UI/data flows unless explicitly told otherwise.
- MUST_NOT | Commit secrets, tokens, credentials, or local env artifacts.
- MUST | Update the affected module README when CLI commands/flags/output, setup/install steps, storage paths, or user-visible behavior changes.

## Delivery
- MUST | Before final response, commit and push to `main` by default.
- MUST_NOT | Create a branch unless explicitly requested or required by workflow.
- MUST | Branch format: `<workspace_branch_prefix>/<TICKET-KEY>_<short_summary>` (lowercase, underscores, 2 words).
- MUST | PR title format: `<TICKET-KEY> <Title>`.
- MUST | First non-empty PR description line must be `<TICKET-KEY>`; preserve template content.
- MUST | Return the PR link.
- MUST | Retry after fixing the issue.
- MUST | Report exact command + exact error and stop.
- MUST | Run repository root `./install.sh` as the final validation step only when install-gate paths change.
- MUST | Install gate is active when any changed path matches `codex-*/**` and does not match `codex-*/README.md`.
- MUST | Skip `./install.sh` when the change set is docs-only (`AGENTS.md`, top-level `README.md`, or only `*/README.md` updates).
- MUST_NOT | Run repository root `./install.sh` for Android app-only changes (`voice/**`, `overlay/**`); validate via Android install/launch flow instead.
- MUST | `install` means install + launch for runnable apps; for CLI/scripts it means install only.

## Tooling
- MUST | Use `gh` unless explicitly told otherwise.
- MUST | Use `acli` unless explicitly told otherwise.
- MUST | Use ADF JSON with `--description-file` / `--body-file`.
- MUST | Return direct links for created/updated/referenced items.
- MUST | Report exact error and stop before API/web fallback.

## macOS Apps
- MUST | No UI/main-thread blocking.
- MUST | Keep UI state deterministic with a single source of truth per feature.
- MUST | Use structured concurrency and explicit cancellation/timeouts.
- MUST | Build, install, and launch when a runnable target/device is available.

## Android Apps
- MUST | No main-thread blocking.
- MUST | Use child `NavHost` per feature when a feature owns multi-screen navigation state; avoid a single app-wide monolithic `NavHost`.
- MUST | Keep presentation as Compose + Mavericks `ViewModel` + Mavericks `State`.
- MUST | Use Mavericks `Async` + `execute` with suspend requests.
- MUST | Use feature-scoped repositories for storage and network.
- MUST | Install and launch app when a device is available.
- MUST | Use `./gradlew :app:installDebug` and `adb shell monkey -p <applicationId> -c android.intent.category.LAUNCHER 1` as default install/launch validation commands.

## Web + TypeScript Apps
- MUST | Feature-scoped modules, not layer-scoped.
- MUST | Keep UI state deterministic with one source of truth per feature.
- SHOULD | Prefer simple composable components over framework-heavy abstractions.
- MUST | Use strict typing; avoid `any` unless justified inline.

## CLI + Scripts
- MUST | Non-interactive and repeatable.
- MUST | Deterministic exit codes; non-zero on errors.
- MUST | Use `set -euo pipefail` with a compatible shell.
- SHOULD | Keep output concise and action-oriented; provide machine-readable output when applicable.
- MUST | Use clear flags/inputs; avoid hidden defaults with side effects.

## Telegram Bot (TypeScript)
- MUST | Keep handlers thin; move business logic into pure/testable services.
- MUST | Handle async errors explicitly; no unhandled promise rejections.
- MUST | Make outbound calls resilient (timeouts, retry/backoff, bounded attempts).
- MUST | Ensure idempotency/deduplication for update handling and side effects.

## Agent Orchestration Systems
- MUST | Workflows/tasks must be idempotent and resumable.
- MUST | Define explicit step inputs/outputs and stable contracts.
- MUST | Persist checkpoints/state needed for recovery before irreversible operations.
- MUST | Enforce per-step timeout, cancellation, and retry budgets.
- MUST | Emit structured logs/metrics/traces with correlation IDs.
- MUST_NOT | Hide cross-step mutable state or rely on implicit global context.

## Validation
- MUST | Run the narrowest relevant tests/checks for changed scope before final response and before any active install gate.
- MUST | Verify runtime behavior on an available target when feasible.
- MUST | Report what could not run, exact blocker, and next actionable command.

## Reference
- INFO | See `AGENTS_REFERENCE.md`.
