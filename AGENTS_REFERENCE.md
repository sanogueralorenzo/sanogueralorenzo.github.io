# AGENTS_REFERENCE

## Rule Format
- `<ID> | <scope> | <level> | <instruction>`
- Precedence: `task-specific > scope-specific > global`
- `AGENTS_REFERENCE.md` is non-normative. `AGENTS.md` is normative.

## Intent
- R01 | * | SHOULD | Optimize for AI tooling execution quality over prose readability.
- R02 | * | SHOULD | Keep enforceable rules in `AGENTS.md`; keep rationale/examples in `AGENTS_REFERENCE.md`.

## Scope Notes
- R10 | android | SHOULD | Prefer child feature `NavHost` over a monolithic app-wide `NavHost` when a feature owns multi-screen navigation state.
- R11 | web/ts-app | SHOULD | Prefer simple composable components over framework-heavy abstractions.
- R12 | cli/script | SHOULD | Keep output concise/action-oriented and provide machine-readable output when useful.

## Validation Matrix
- R20 | install-gate | SHOULD | If changed paths match `codex-*/**` (excluding `codex-*/README.md`), run narrow checks then root `./install.sh`.
- R21 | android-only-change | SHOULD | If only `voice/**` or `overlay/**` changed, run narrow checks then `./gradlew :app:installDebug` and `adb shell monkey -p <applicationId> -c android.intent.category.LAUNCHER 1`.
- R22 | docs-only-change | SHOULD | If changes are docs-only (`AGENTS.md`, root `README.md`, or only `*/README.md`), skip install gates.

## Delivery Patterns
- R30 | code-change | SHOULD | Use default flow: edit -> validate -> commit -> push `main`.
- R31 | pr-flow | SHOULD | Use branch/PR flow only when explicitly requested or workflow-required.

## Tooling Patterns
- R40 | github | SHOULD | Use `gh` for GitHub workflows.
- R41 | jira | SHOULD | Use `acli` for Jira workflows and ADF JSON files for description/comment bodies.
- R42 | artifact-links | SHOULD | Include direct links for created/updated/referenced artifacts.
- R43 | cli-auth-failure | SHOULD | On required CLI/auth failures, report exact error and stop before fallback.

## Update Checklist
- R50 | module-change | SHOULD | If module behavior/help/setup/storage changed, update that module README in the same change.
- R51 | rule-maintenance | SHOULD | Keep rule IDs stable; append new IDs instead of reusing old IDs for new semantics.
