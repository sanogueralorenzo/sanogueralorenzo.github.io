# Verification

## Required checks

Build Debug and Release with `dotnet build` and `dotnet build -c Release`. For behavior or visual changes, launch with `./run.command` and use ordinary controls. Do not create automated tests, inject game state, or substitute an art sample for gameplay verification.

Check the affected behavior at normal camera scale. For world changes, include shore collision, reachable encounters, chunk unloading/revisits and bounded caches. For combat changes, include pause/resume, fishing, progression and sustained play. Save unedited F12 screenshots with paired telemetry and report runtime errors, measurements and coverage limits. Update the baseline, gaps and evidence below.

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

## Evidence

PNG files are unedited native captures; matching TXT files contain telemetry. Older captures may show superseded behavior.

| Evidence | Coverage |
| --- | --- |
| [Home](../evidence/sparse-rewards-home.png), [chest](../evidence/sparse-rewards-chest.png), [collected](../evidence/sparse-rewards-chest-collected.png) | Final reward art and beach access |
| [Barrel](../evidence/sparse-rewards-barrel.png), [collected](../evidence/sparse-rewards-barrel-collected.png) | Sparse contact pickup |
| [Unloaded](../evidence/sparse-rewards-unloaded.png), [revisit](../evidence/sparse-rewards-revisit.png) | Chest depletion survives streaming |
| [Giant chest](../evidence/sparse-rewards-giant-before-trim.png), [collected](../evidence/sparse-rewards-giant-collected.png) | Giant shore access; before final gold trim |
| [Barrel revisit](../evidence/sparse-rewards-barrel-revisit.png) | Barrel depletion survives streaming |
| [Reward runtime](../evidence/sparse-rewards-final-runtime.txt), [exploration runtime](../evidence/sparse-rewards-exploration-runtime.txt) | Complete reward sessions |
| [Progression runtime](../evidence/gradual-runtime.txt) | Gradual buildup and 22:11 victory; mostly ×3 play |

For older checks, find captures by prefix: `gradual-` (pacing), `puffer-` (fuse/explosion), `giant-` (islands), `diorama-` (native presentation and flows). Read telemetry alongside screenshots; a still image cannot establish motion or timing.

## Research provenance

Code and art are original; no proprietary code or assets are imported. These findings describe inspected versions only.

- **Sno:** informed deterministic randomness, bounded placement, clearance and chunk ownership; implementation is independent.
- **Megabonk:** partial [spawning disassembly](megabonk-spawning-disassembly.txt) informed separate spawn income and population targets. [Silver inspection](megabonk-silver-disassembly.txt) established a time gate; initial setup and other reward paths remain unresolved. Our balance and random 45–90-second silver interval are custom.
- **Nova Drift:** demo descriptions informed readable combinations and combat. No implementation or tuning was recovered; our progression uses simple weapon/stat choices.
