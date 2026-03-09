# AGENTS_REFERENCE_V4
- Non-normative companion to `AGENTS_V4.md`; keep optional guidance only.
- Module map: `codex-auth` Rust CLI+watcher; `codex-sessions` Rust CLI+thread-title watcher; `codex-remote` TS bot CLI; `codex-menubar` Swift mac app; `codex-agents` Bash CLI; `voice`/`overlay` Android apps; `site` Hugo static site.
- Install entrypoints: `codex-*/scripts/install.sh`; root `./install.sh` installs auth+sessions+remote+menubar; Android modules install via Gradle `:app:installDebug`.
- Runtime targets: Android packages `com.sanogueralorenzo.voice` and `com.sanogueralorenzo.overlay`; menubar app install target `/Applications/Codex Menu Bar.app`.
- Fallbacks: if `cargo test` blocked use `cargo check`; if TS build drifts run `npm install` once then retry; if no Android device run assemble-only and report blocker; if `hugo` missing report install command.
- Reporting: always include checks run/skipped, install/runtime gates fired, exact blocker commands/errors, and direct links for external artifacts.
- Optional engineering bias: explicit code paths, feature-scoped modules, deterministic state ownership, thin handlers, idempotent workflows.
