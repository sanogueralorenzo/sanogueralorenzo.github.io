# AGENTS_REFERENCE_V3

## Rule Format
- `<ID> | <scope> | <level> | <instruction>`
- Precedence: `task-specific > scope-specific > global`
- `AGENTS_REFERENCE_V3.md` is non-normative. `AGENTS_V3.md` is normative.

## Intent
- R01 | * | SHOULD | Keep `AGENTS_V3.md` execution-only and deterministic.
- R02 | * | SHOULD | Keep this file compact and optional.

## Module Map
- M01 | codex-auth/** | INFO | Rust CLI; install: `codex-auth/scripts/install.sh`; verify: `cargo test`.
- M02 | codex-sessions/** | INFO | Rust CLI; install: `codex-sessions/scripts/install.sh`; verify: `cargo test`.
- M03 | codex-remote/** | INFO | TypeScript CLI; install: `codex-remote/scripts/install.sh`; verify: `npm run typecheck && npm run build`.
- M04 | codex-menubar/** | INFO | Swift macOS app; install/launch: `codex-menubar/scripts/install.sh`; verify: `swift build -c release --product CodexMenuBar`.
- M05 | codex-agents/** | INFO | Bash CLI; install: `codex-agents/scripts/install.sh`; verify: `bash scripts/codex-agents --help`.
- M06 | voice/** | INFO | Android app `com.sanogueralorenzo.voice`; verify: `./gradlew :app:assembleDebug`; runtime: `installDebug + monkey`.
- M07 | overlay/** | INFO | Android app `com.sanogueralorenzo.overlay`; verify: `./gradlew :app:assembleDebug`; runtime: `installDebug + monkey`.
- M08 | site/** | INFO | Hugo site; verify/build: `hugo --minify`.

## Fallbacks
- F01 | rust-check | SHOULD | If `cargo test` blocked, fallback to `cargo check` and report blocker.
- F02 | ts-check | SHOULD | If `npm run typecheck && npm run build` fails from dependency drift, run `npm install` once then retry.
- F03 | android-runtime | SHOULD | If no device available, run assemble-only and report missing device for install/launch.
- F04 | site-check | SHOULD | If `hugo` missing, report missing binary and next install command.

## Reporting
- X01 | validation-report | SHOULD | Report checks run, checks skipped, and blockers with exact commands.
- X02 | install-report | SHOULD | Report which install/runtime gates fired and which commands executed.
