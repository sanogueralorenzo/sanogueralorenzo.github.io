# AGENTS_REFERENCE

Non-normative guidance for agents. Enforcement lives in `AGENTS.md`.

## Intent
- Optimize for AI tooling execution quality, not prose readability.
- Keep deterministic policy in `AGENTS.md`; keep rationale/examples here.

## Scope Notes
- Android nav guidance: prefer child feature `NavHost` over monolithic app-wide `NavHost` when a feature owns multi-screen state.
- Web/TS design guidance: prefer simple composable components over framework-heavy abstractions.
- CLI output guidance: keep output concise/action-oriented; include machine-readable output when useful.

## Validation Matrix
- `codex-*/**` changed (excluding `codex-*/README.md`): run narrow tests/checks, then run root `./install.sh`.
- Android app-only changed (`voice/**`, `overlay/**`): run narrow tests/checks, then `./gradlew :app:installDebug`, then launch via `adb shell monkey -p <applicationId> -c android.intent.category.LAUNCHER 1`.
- Docs-only changed (`AGENTS.md`, root `README.md`, or only `*/README.md`): skip install gates.

## Delivery Patterns
- Default flow: edit -> validate -> commit -> push `main`.
- Branch/PR flow only when explicitly requested or workflow-required.

## Tooling Patterns
- GitHub: use `gh`.
- Jira: use `acli` + ADF JSON bodies (`--description-file` / `--body-file`).
- Created/updated/referenced artifacts should include direct links.
- On CLI/auth failures for required tools, report exact error and stop before fallback.

## Update Checklist
- If a module changes user-facing behavior, CLI help/flags/output, setup/install steps, or storage paths, update that module README in the same change.
- Keep rule IDs stable where possible; append new IDs instead of reusing old IDs for different semantics.
