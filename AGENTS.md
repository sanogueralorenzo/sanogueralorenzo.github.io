# AGENTS

## Rule Format
- `<ID> | <scope> | <level> | <instruction>`
- Precedence: `task-specific > scope-specific > global`
- `AGENTS.md` is normative. `AGENTS_REFERENCE.md` is non-normative.

## Global
- G01 | * | MUST | Prefer explicit, clear code over clever code.
- G02 | * | MUST | Make forward-only changes; no legacy/back-compat unless requested.
- G03 | * | MUST | Update call sites and tests in the same change.
- G04 | * | MUST | Delete replaced code and keep one source of truth.
- G05 | * | MUST | Keep functions small, explicit, and side-effect aware.
- G07 | * | MUST_NOT | Add unnecessary abstraction or layer-oriented packaging.
- G08 | * | MUST | Use feature-scoped modules.
- G10 | * | MUST | Use explicit loading/error/empty states for async UI/data flows unless explicitly told otherwise.
- G11 | * | MUST_NOT | Commit secrets, tokens, credentials, or local env artifacts.
- G12 | module-change | MUST | Update affected module README when CLI/help output, setup/install, storage paths, or user-visible behavior changes.

## Delivery
- D01 | code-change | MUST | Before final response, commit and push to `main` by default.
- D02 | code-change | MUST_NOT | Create a branch unless explicitly requested or required by workflow.
- D03 | branch-required | MUST | Branch format: `<workspace_branch_prefix>/<TICKET-KEY>_<short_summary>` (lowercase, underscores, 2 words).
- D04 | pr-required | MUST | PR title format: `<TICKET-KEY> <Title>`.
- D05 | pr-required | MUST | First non-empty PR description line must be `<TICKET-KEY>`; preserve template content.
- D06 | pr-required | MUST | Return the PR link.
- D07 | delivery-failure | MUST | Retry after fixing the issue.
- D08 | blocked-after-retries | MUST | Report exact command + exact error and stop.
- D10 | install-gate | MUST | Run root `./install.sh` only when install-gate paths change.
- D10a | install-gate | MUST | Install gate is active when any changed path matches `codex-*/**` and does not match `codex-*/README.md`.
- D10b | install-gate | MUST | Skip root `./install.sh` for docs-only changes (`AGENTS.md`, root `README.md`, or only `*/README.md`).
- D10c | android-only-change | MUST_NOT | Run root `./install.sh` for Android app-only changes (`voice/**`, `overlay/**`).
- D11 | install-semantics | MUST | `install` means install+launch for runnable apps; install-only for CLI/scripts.

## Tooling
- T01 | github | MUST | Use `gh` unless explicitly told otherwise.
- T02 | jira | MUST | Use `acli` unless explicitly told otherwise.
- T03 | jira-write | MUST | Use ADF JSON with `--description-file` / `--body-file`.
- T04 | gh/acli/slack | MUST | Return direct links for created/updated/referenced items.
- T05 | cli-install-or-auth-failure | MUST | Report exact error and stop before API/web fallback.

## macOS Apps
- M01 | mac-app | MUST | No UI/main-thread blocking.
- M02 | mac-app | MUST | Keep UI state deterministic with one source of truth per feature.
- M03 | mac-app | MUST | Use structured concurrency with explicit cancellation/timeouts.
- M04 | mac-app-behavior-change | MUST | Build, install, and launch when a runnable target/device is available.

## Android Apps
- A01 | android | MUST | No main-thread blocking.
- A03 | android | MUST | Keep presentation as Compose + Mavericks `ViewModel` + Mavericks `State`.
- A04 | android | MUST | Use Mavericks `Async` + `execute` with suspend requests.
- A05 | android | MUST | Use feature-scoped repositories for storage and network.
- A06 | android-behavior-change | MUST | Install and launch app when a device is available.
- A07 | android-behavior-change | MUST | Use `./gradlew :app:installDebug` and `adb shell monkey -p <applicationId> -c android.intent.category.LAUNCHER 1` by default.

## Web + TypeScript Apps
- W01 | web/ts-app | MUST | Use feature-scoped modules, not layer-scoped modules.
- W02 | web/ts-app | MUST | Keep UI state deterministic with one source of truth per feature.
- W04 | typescript | MUST | Use strict typing; avoid `any` unless justified inline.

## CLI + Scripts
- C01 | cli/script | MUST | Keep execution non-interactive and repeatable.
- C02 | cli/script | MUST | Use deterministic exit codes; non-zero on errors.
- C03 | shell-script | MUST | Use `set -euo pipefail` with a compatible shell.
- C05 | cli/script | MUST | Use clear flags/inputs; avoid hidden defaults with side effects.

## Telegram Bot (TypeScript)
- B01 | telegram-bot | MUST | Keep handlers thin; move business logic into pure/testable services.
- B02 | telegram-bot | MUST | Handle async errors explicitly; no unhandled promise rejections.
- B03 | telegram-bot | MUST | Make outbound calls resilient (timeouts, retry/backoff, bounded attempts).
- B04 | telegram-bot | MUST | Ensure idempotency/deduplication for update handling and side effects.

## Agent Orchestration Systems
- O01 | orchestration | MUST | Workflows/tasks must be idempotent and resumable.
- O02 | orchestration | MUST | Define explicit step inputs/outputs and stable contracts.
- O03 | orchestration | MUST | Persist checkpoints/state needed for recovery before irreversible operations.
- O04 | orchestration | MUST | Enforce per-step timeout, cancellation, and retry budgets.
- O05 | orchestration | MUST | Emit structured logs/metrics/traces with correlation IDs.
- O06 | orchestration | MUST_NOT | Hide cross-step mutable state or rely on implicit global context.

## Validation
- V01 | any-change | MUST | Run the narrowest relevant tests/checks for changed scope before final response and before any active install gate.
- V02 | behavior-change | MUST | Verify runtime behavior on an available target when feasible.
- V03 | unable-to-validate | MUST | Report what could not run, exact blocker, and next actionable command.
