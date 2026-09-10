# Verification

## Required checks

Build Debug and Release with `dotnet build` and `dotnet build -c Release`. For behavior or visual changes, launch with `./run.command` and use ordinary controls. Do not create automated tests, inject game state, or substitute an art sample for gameplay verification.

Check the affected behavior at normal camera scale. For world changes, include shore collision, reachable encounters, chunk unloading/revisits and bounded caches. For combat changes, include pause/resume, progression, pickups and sustained play. Save unedited F12 screenshots with paired telemetry and report runtime errors, measurements and coverage limits. Update the baseline, gaps and evidence below.

## Current visual baseline — 2026-09-10

The procedural pirate hulls, readable flag and height-based health bar remain. Orthographic zoom is 0.70, ground foreshortening is 0.78 (about 51° elevation), and boat geometry is 15% larger than its original proportions. Spawn is restored to the original dock position. Voyage speeds remain ×1 / ×2 / ×3 / ×10 / ×20.

Islands retain rounded outward coastline offsets, a positive shelf width, visible inner shallows, full prop-footprint clearance and the original simple sand–dry grass–green shader. The shelf envelope is radius × 0.60, clamped to 0.50–2.8 world units before seeded variation; coastline width varies smoothly between 56–100% of that envelope. Later halo shading, warped grass variation and sparse-islet rules are removed. Simulation coastlines, encounters and collision footprints are unchanged.

Debug and Release passed with zero warnings/errors. The macOS export completed, the app was reinstalled and its signature verified. Native art checks through `run.command` cover the [regression crescent](../evidence/cleanup-crescent.png), [narrow radius-95 island](../evidence/cleanup-small.png), and [radius-720 island](../evidence/cleanup-large.png) at normal camera scale.

Installed-app play checked sailing, [shore contact](../evidence/cleanup-shore.png), steering away, and weapon/boat upgrade selection. [Offshore telemetry](../evidence/cleanup-offshore.txt) records 160.4 active sailing seconds, projection `(0.7, 0.54599994)`, 25 loaded chunks and 10 cached scenery entries; the home harbor is absent after unloading. Native captures confirm [×10](../evidence/cleanup-offshore.png) and [×20](../evidence/cleanup-speed-20.png). No runtime or shader errors were observed in the recorded startup/export/art logs.

Verification stopped at the user's request. The return/revisit check and speed wrap to ×1 were not completed; the latter remains source-verified. This is a short streaming check, not proof of long-run cache stability. No full voyage, all-boat sweep, all-seed sweep or pickup replay was performed.

## Verified baseline — 2026-09-09

Latest upgrade-menu check: Debug and Release passed with zero warnings/errors. Native play verified level 2 offered three weapon-only rows, clicking a row applied Harpoon and resumed sailing, and level 3 offered three boat-only rows. Each row displays its icon beside the name and benefit. See [weapon rows](../evidence/upgrade-weapon-rows.png) and [boat rows](../evidence/upgrade-boat-rows.png), with paired telemetry. Maxed-category fallback and queued multiple levels were source-reviewed, not runtime-tested. No broader replay was run.

Debug and Release builds passed with zero warnings/errors. Native sessions used Godot 4.7.2 .NET, Forward+ / Metal on Apple M3 Max; no runtime errors were observed.

- **Progression:** Gunboat reached level 5 at 5:31, mostly at ×3. Verified Cannon and Reach upgrades, adding Lightning as a second weapon, and a Hull upgrade. Upgrade menus paused combat and selections resumed sailing.
- **Pickups:** a barrel remained undepleted while the full-health boat overlapped it. After Hull increased maximum health to 125, collecting another barrel restored health from 100 to 125 and depleted the barrel. A beach chest was collected from the water. Its 12-XP reward is source-verified; the earlier capture format did not record current XP.
- **Harbor and world:** the starting harbor radius is 280, up from 140. Gunboat departure and Aura shore approach were checked. Pressing E at home did not open an interaction. Offshore streaming remained at 25 chunks, and the home harbor unloaded when sailing away. Source review confirms procedural landmarks generate only islands.
- **Performance:** the 125-second active Gunboat session reported 8.39 ms mean frame time and 8.37 ms p99 at its final capture, with a peak of four enemies and six shots. This is not a stress benchmark.

## Coverage gaps

Checks stopped at the user's request to keep verification brief. The final barrel health-cross winding correction built and launched, but its appearance was not rechecked at a pickup. No new full 22-minute balance replay, maxed-build healing fallback run, all-boat pickup sweep, or depleted-pickup unload/revisit check. Mage departure, maximum-crowd performance and long endless play remain unverified for this change. Healing availability and XP pacing need ordinary play feedback.

## Evidence

PNG files are unedited native captures, paired with TXT telemetry. The main session predates only the final health-cross winding correction, silver-icon cleanup, removal of unused tier helpers and extra XP telemetry. Older repository captures may show removed fishing, shops and gold.

| Evidence | Coverage |
| --- | --- |
| [Upgrade applied](../evidence/simple-upgrade-applied.png) | Level 2 Cannon upgrade and resumed sailing |
| [Full-health barrel](../evidence/simple-full-health-barrel.png) | Boat overlapping an undepleted barrel at full health |
| [Chest collected](../evidence/simple-chest-collected.png) | Water access and chest depletion |
| [Healing collected](../evidence/simple-healing-collected.png) | 125/125 health and barrel depletion after Hull upgrade |
| [Aura shore](../evidence/simple-aura-shore.png) | Enlarged starting island in the final build |
| [Gameplay runtime](../evidence/simple-runtime.txt), [final build runtime](../evidence/simple-final-runtime.txt) | Native session telemetry and startup logs |

## Research provenance

Code and art are original; no proprietary code or assets are imported. These findings describe inspected versions only.

- **Sno:** informed deterministic randomness, bounded placement, clearance and chunk ownership; implementation is independent.
- **Megabonk:** partial [spawning disassembly](megabonk-spawning-disassembly.txt) informed separate spawn income and population targets. [Silver inspection](megabonk-silver-disassembly.txt) established a time gate; initial setup and other reward paths remain unresolved. Our balance and random 45–90-second silver interval are custom.
- **Nova Drift:** demo descriptions informed readable combinations and combat. No implementation or tuning was recovered; our progression uses simple weapon/stat choices.
