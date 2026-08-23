# Release-candidate plan and checklist

Last reviewed: 2026-08-23 · Target: PC / Steam / single-player · Status: not a release candidate

Nothing here authorizes publishing, uploading, purchasing, contacting third
parties, or changing an external store. Those actions require explicit approval.

## Product acceptance

- [ ] Core downhill movement is polished, stable, predictable, and enjoyable on
  the handcrafted regression course and generated terrain.
- [ ] A complete launch → run → completion/crash → results → fast restart flow
  works in 10–15 minutes.
- [ ] Frost, Dunes, and Ashlands are mechanically and audiovisually distinct.
- [ ] Deterministic generation produces validated, authored-feeling viable routes;
  failed seeds reproduce and soak thresholds pass.
- [ ] Upgrades create meaningful bounded variation without mandatory picks or
  permanent-stat meta progression.
- [ ] Keyboard and controller gameplay/menu operation and reconnection pass.
- [ ] Title, pause, settings, remapping, saving/migration, onboarding, HUD, upgrade
  choice, results, seed display/entry, and restart are complete.
- [ ] Camera, UI, art, lighting, weather, VFX, music, surface/speed audio, mixing,
  and haptics form one intentional experience.
- [ ] Accessibility baseline in `game-design.md` passes a focused review.
- [ ] Every placeholder is replaced, intentionally retained, or accepted in the
  placeholder register with no release-facing debug artifacts.

## Quality and platform acceptance

- [ ] Minimum and recommended performance budgets pass in release exports on
  representative hardware; captures/results are archived by build and seed.
- [ ] Movement, generation, seed, save/migration, controller, keyboard, menus,
  display modes, alt-tab/focus, pause, restart, long-session, upgrades, transitions,
  frame-rate, clean-install, and exported-build test matrices pass.
- [ ] No open P0 or P1 defects; every remaining P2 has an explicit ship decision.
- [ ] Windows x86_64 release export is reproducible from a clean checkout with the
  pinned Godot patch and documented template/tool versions.
- [ ] Steam Deck/Linux is either tested to its declared bar and documented as
  supported, or explicitly excluded from store claims.
- [ ] Save location, reset/recovery, backup, and migration behavior is documented.
- [ ] Crash/log collection preserves useful seed/build/state data and avoids
  unnecessary personal information.

## Compliance and release materials

- [ ] Semantic game version/build identifier is visible in results/logs.
- [ ] Export presets, product name, application icon, legal/copyright strings, and
  executable metadata are final.
- [ ] Credits are complete; every third-party asset/library/font/plugin has verified
  provenance, license text, attribution, and commercial-distribution permission.
- [ ] Store description, short description, feature list, accessibility statement,
  minimum/recommended specifications, and known-issues text are drafted and honest.
- [ ] Screenshot capture list, trailer shot list, and capsule-art size/source
  requirements are complete; candidate media contains no debug/placeholder content.
- [ ] Steam Input, achievements, and Steam Cloud have a recorded include/defer
  decision; credentials-dependent work is tested only when authorized.
- [ ] Clean install/uninstall and fresh/old/corrupt save scenarios pass.
- [ ] Release build and symbols/logging artifacts are backed up; rollback build,
  prior save compatibility, and emergency disable/communication steps are written.
- [ ] A final limitation review shows every gap is consciously accepted rather
  than accidentally unfinished.

## Candidate test record template

For each candidate record: version/commit; Godot and export-template versions;
platform/hardware/driver; build checksum; test matrix result; generation batch
count and failed seeds; full-run count; performance captures; save fixtures;
open/accepted defects; asset/license audit result; clean-install result; and final
go/no-go owners. A failed applicable item returns the project to the relevant phase.

