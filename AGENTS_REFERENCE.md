# AGENTS_REFERENCE

## Rule Format
- `<ID> | <scope> | <level> | <instruction>`
- Precedence: `task-specific > scope-specific > global`
- `AGENTS_REFERENCE.md` is non-normative. `AGENTS.md` is normative.

## Intent
- R01 | * | SHOULD | Optimize for AI tooling execution quality over prose readability.
- R02 | * | SHOULD | Keep enforceable rules in `AGENTS.md`; keep rationale/examples in `AGENTS_REFERENCE.md`.

## Global Guidance
- R05 | * | SHOULD | Keep functions small, explicit, and side-effect aware.
- R08 | * | SHOULD | Use feature-scoped modules.
- R10 | * | SHOULD | Use explicit loading/error/empty states for async UI/data flows unless explicitly told otherwise.

## Android Guidance
- R20 | android | SHOULD | Prefer child feature `NavHost` over a monolithic app-wide `NavHost` when a feature owns multi-screen navigation state.
- R23 | android | SHOULD | Keep presentation as Compose + Mavericks `ViewModel` + Mavericks `State`.
- R24 | android | SHOULD | Use Mavericks `Async` + `execute` with suspend requests.
- R25 | android | SHOULD | Use feature-scoped repositories for storage and network.

## Web + TypeScript Guidance
- R30 | web/ts-app | SHOULD | Use feature-scoped modules instead of layer-scoped modules.
- R31 | web/ts-app | SHOULD | Keep UI state deterministic with one source of truth per feature.
- R32 | typescript | SHOULD | Use strict typing and avoid `any` unless justified inline.
- R33 | web/ts-app | SHOULD | Prefer simple composable components over framework-heavy abstractions.

## Telegram Bot Guidance
- R40 | telegram-bot | SHOULD | Keep handlers thin; move business logic into pure/testable services.
- R41 | telegram-bot | SHOULD | Handle async errors explicitly; avoid unhandled promise rejections.
- R42 | telegram-bot | SHOULD | Make outbound calls resilient with timeouts and bounded retry/backoff.
- R43 | telegram-bot | SHOULD | Ensure idempotency/deduplication for update handling and side effects.

## Orchestration Guidance
- R50 | orchestration | SHOULD | Keep workflows/tasks idempotent and resumable.
- R51 | orchestration | SHOULD | Define explicit step inputs/outputs with stable contracts.
- R52 | orchestration | SHOULD | Persist checkpoints/state needed for recovery before irreversible operations.
- R53 | orchestration | SHOULD | Enforce per-step timeout, cancellation, and retry budgets.
- R54 | orchestration | SHOULD | Emit structured logs/metrics/traces with correlation IDs.
- R55 | orchestration | SHOULD_NOT | Hide cross-step mutable state or rely on implicit global context.

## Validation Matrix
- R60 | install-gate | SHOULD | If changed paths match `codex-*/**` (excluding `codex-*/README.md`), run narrow checks then root `./install.sh`.
- R61 | android-only-change | SHOULD | If only `voice/**` or `overlay/**` changed, run narrow checks then `./gradlew :app:installDebug` and `adb shell monkey -p <applicationId> -c android.intent.category.LAUNCHER 1`.
- R62 | docs-only-change | SHOULD | If changes are docs-only (`AGENTS.md`, root `README.md`, or only `*/README.md`), skip install gates.

## Delivery Patterns
- R70 | code-change | SHOULD | Use default flow: edit -> validate -> commit -> push `main`.
- R71 | pr-flow | SHOULD | Use branch/PR flow only when explicitly requested or workflow-required.

## Tooling Patterns
- R80 | github | SHOULD | Use `gh` for GitHub workflows.
- R81 | jira | SHOULD | Use `acli` for Jira workflows and ADF JSON files for description/comment bodies.
- R82 | artifact-links | SHOULD | Include direct links for created/updated/referenced artifacts.
- R83 | cli-auth-failure | SHOULD | On required CLI/auth failures, report exact error and stop before fallback.

## Update Checklist
- R90 | module-change | SHOULD | If module behavior/help/setup/storage changed, update that module README in the same change.
- R91 | rule-maintenance | SHOULD | Keep rule IDs stable; append new IDs instead of reusing old IDs for new semantics.
