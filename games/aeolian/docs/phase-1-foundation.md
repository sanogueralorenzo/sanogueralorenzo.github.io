# Phase 1 technical-foundation gate record

Last updated: 2026-08-23 · Status: **passed 2026-08-23**

## Objective

Provide a reliable production spine for iteration without depending on unfinished
gameplay: launch/state/pause ownership, keyboard/gamepad intent and binding format,
versioned settings/profile persistence, deterministic seed domains, diagnostics,
headless tests, performance telemetry, a handcrafted course shell, and export
packaging.

## Integrated deliverables

- Persistent `levels/main.tscn` shell and guarded state machine covering boot,
  title, loading, intro, descent, pause, transition, crash, and results states.
- Minimal title and pause UI with keyboard/gamepad focus defaults; focus-loss and
  active-controller disconnect pause active descent.
- Named keyboard/common-gamepad actions, typed input intent, active-device signals,
  haptic ownership, and primitive canonical binding serialization.
- Versioned settings and profile schemas; validated values, explicit v0 profile
  migration, verified temporary writes, previous-file backups, recovery, unknown
  supported-key preservation, corrupt profile quarantine, and future-schema
  overwrite protection.
- Versioned SHA-256 domain seed derivation with independent RNG instances and
  pinned regression vectors.
- Structured log facade, debug-build-only performance overlay, frame/physics/draw/
  node monitors, and seed/build-capable diagnostic seams.
- Handcrafted 3D foundation course with lighting, collision, gentle slope, bank,
  route markers, camera, and explicit notice that movement is not implemented.
- Repository-owned tests/check scripts and Windows/Linux debug/release presets.

## Automated evidence

- `./scripts/check.sh`: project/editor scan, 89 assertions across 23 focused tests,
  settings/profile/input service round trips, and bounded launch → course → pause →
  resume → title cleanup smoke. Passed 2026-08-23 with no logged errors or leaks.
- `./scripts/export-smoke.sh`: checksum-verified Godot 4.7.2 stable templates built
  Windows x86_64 PE and Linux x86_64 ELF debug/release artifacts; `file` and SHA-256
  inspection passed 2026-08-23.
- Export success is packaging evidence only. This macOS host cannot prove Windows
  D3D12, Linux Vulkan, target input/display/focus, Steam/Proton, or target hardware
  performance behavior.

## Independent review and risks

Two read-only tooling/architecture reviews informed key normalization, domain RNG
versioning, save/settings future-schema policy, explicit state transitions, and the
custom test runner. A final independent implementation review reproduced checks,
identified migration/backup/finite-number defects that were fixed with regression
tests, and reported no unresolved verified code defect.

The highest later risk remains movement contact and feel; none of this foundation
validates player physics. The temporary icon, primitive course art, and default
font are tracked placeholders. Full rebinding UI, graphics/audio settings screens,
and final navigation/accessibility belong to Phase 8; the ownership and persistence
seams exist now.

## Gate outcome

**Passed 2026-08-23.** A native macOS Metal Forward+ diagnostic run rendered
1280×720 title, handcrafted course, and pause frames. The captures were visually
inspected for clipping, focus treatment, readability, scene replacement, and pause
dimming; an initial always-visible debug overlay conflict was corrected. The same
run injected the actual `ui_accept` and `pause` actions and asserted focus on Start
and Resume, exercising title → course → pause → resume through UI input routing.

The final foundation checks and Windows/Linux debug/release packaging passed after
review fixes. The foundation is hardened and retained. The primitive course and
default visual/audio assets are intentional disposable placeholders; no player
movement prototype exists to retain. Phase 2 may begin.

Carried evidence gaps are not hidden: no physical gamepad or Windows/Linux target
runtime was available in this environment. These do not block the architecture
gate, but keyboard/gamepad movement playtesting is mandatory for Phase 2 and target
OS/hardware/exported runtime tests remain release gates.
