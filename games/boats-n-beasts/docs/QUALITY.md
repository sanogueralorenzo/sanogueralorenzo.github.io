# Verification

## Required checks

Build Debug and Release with `dotnet build` and `dotnet build -c Release`. For behavior or visual changes, launch with `./run.command` and use ordinary controls. Do not create automated tests, inject game state, or substitute an art sample for gameplay verification.

Check the affected behavior at normal camera scale. For world changes, include shore collision, reachable encounters, chunk unloading/revisits and bounded caches. For combat changes, include pause/resume, fishing, progression and sustained play. Save unedited F12 screenshots with paired telemetry and report runtime errors, measurements and coverage limits. Keep selected evidence in the [index](../evidence/README.md); update the baseline and gaps below.

## Verified baseline — 2026-09-09

Debug and Release passed with zero warnings/errors. Reviewed native sessions used Godot 4.7.2 .NET, Forward+ / Metal on Apple M3 Max; logs were clean.

- **Rewards:** two voyages verified small and giant island chest access from water, barrel contact, gold amounts and depletion after unloading/revisiting. The earlier giant/barrel route predates only the chest's gold-trim refinement.
- **Progression:** a Gunboat with Cannon/Lightning won at 22:11. Most of the run used ×3, returning to ×1 at 21:22; active wall time was 478 seconds. The boss was absent at 21:58 and appeared at 22:00. Pause/handbook state stayed identical across 17 seconds. Observed regular population peaked at 18; this does not exercise the 64-enemy ceiling.
- **Islands:** native samples covered all eight giant families; gameplay reached a giant island and stopped at its visible coast. Samples alone do not establish navigability.
- **Puffers:** native play showed chase, fuse and explosions. Source review confirmed only the boss creates hostile shots; isolated cannon hits now end instead of reversing toward the player. The original apparent puffer shot was not reproduced.
- **Existing flows:** earlier native checks covered all boat starts, steering/boost, fishing and catch sale, harbor purchases, free upgrades, pause/resume and streaming. Older evidence can show superseded art or mechanics.

The final reward route sampled 12.05 ms mean frame time and 18.75 ms p99. This is not a worst-case benchmark.

## Coverage gaps

No exhaustive seed/family sweep, all-boat pickup check, maximum-crowd stress run or full 22-minute economy replay after the reward changes. One winning build does not establish balance across boats and upgrades. Placement percentages are candidate configuration, not measured encounter frequency. Long endless play and lower-end hardware remain unverified.
