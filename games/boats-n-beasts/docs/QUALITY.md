# Verification

## Required checks

Build Debug and Release with `dotnet build` and `dotnet build -c Release`. For behavior or visual changes, launch with `./run.command` and use ordinary controls. Do not create automated tests, inject game state, or substitute an art sample for gameplay verification.

Check the affected behavior at normal camera scale. For world changes, include shore collision, reachable encounters, chunk unloading/revisits and bounded caches. For combat changes, include pause/resume, progression, pickups and sustained play. Save unedited F12 screenshots with paired telemetry and report runtime errors, measurements and coverage limits. Update the baseline, gaps and evidence below.

## Procedural island review — 2026-09-10

Revisited the shoreline at the final 49° camera elevation and wider view. Underwater shelves retain rounded coastline offsets and a positive minimum width, with stronger long asymmetric width variation (44–100% of the size-scaled envelope). Broader, lower-contrast seabed patches replace dense mottling; caustics are quieter and surf dissolves in separated arcs. The inner shelf remains opaque enough to avoid a sand-colored outline, while its outer edge fades into open water. Grass uses broad warped patches, subtle interior color variation and a gentler color blend within a narrower transition envelope. Small or narrow islets have fewer props; coastal rocks form a few outcrops separated by clear beaches. All art remains procedural. Collision outlines, landmark placement and treasure-clearance rules are unchanged.

Debug and Release passed with zero warnings/errors. The native sample launched through `run.command`; all eight coastline families were inspected at normal playing scale, covering radii 95, 200, 330, 355.7 and 720. The [before](../evidence/island-review-before.png) and [after crescent](../evidence/island-review-crescent.png) show the same regression island with the same camera. Final examples:

| Shape | Native capture |
| --- | --- |
| Compact, radius 200 | [View](../evidence/island-review-compact.png) |
| Long, radius 95 | [View](../evidence/island-review-long.png) |
| Crescent, radius 355.7 | [View](../evidence/island-review-crescent.png) |
| Lobed, radius 720 | [View](../evidence/island-review-lobed.png) |
| Headland, radius 330 | [View](../evidence/island-review-headland.png) |
| Bean, radius 200 | [View](../evidence/island-review-bean.png) |
| Twin, radius 95 | [View](../evidence/island-review-twin.png) |
| Scalloped, radius 200 | [View](../evidence/island-review-scalloped.png) |

The macOS export completed without warnings/errors; the reinstalled app launched with Forward+ / Metal and its signature verified. Ordinary installed-app play checked harbor departure, [shore approach](../evidence/island-review-shore-approach.png), steering away after contact, level-up selection, [procedural islands offshore](../evidence/island-review-gameplay.png), and [revisiting them](../evidence/island-review-revisit.png). Paired telemetry records 109.6 active sailing seconds, level 3, 25 loaded chunks, and 16.74 ms mean frame time. The home harbor leaves the loaded set in [offshore telemetry](../evidence/island-review-offshore.txt) and returns in [revisit telemetry](../evidence/island-review-revisit.txt); scenery cache counts change from 8 to 9 to 8 across those captures. This is a short streaming check, not a long-run cache or stress benchmark.

No errors were observed in the recorded [art runtime](../evidence/island-review-art-runtime.txt), export or [initial installed runtime](../evidence/island-review-installed-runtime.txt). Final-voyage evidence is provided by native F12 captures and telemetry. Every seed/size combination, treasure collection and extended high-speed combat were not rechecked. The previously enlarged boat mesh can visually overhang a small island at collision contact; this pass does not change its existing collision footprint.

## Slightly lower camera — 2026-09-10

Ground foreshortening is now 0.75, lowering camera elevation from 51.26° to 48.59°. This increases the original 0.84-to-0.78 foreshortening adjustment by 50%. Zoom, boat geometry and the five speed options remain unchanged.

Debug and Release passed with zero warnings/errors; macOS export was clean. The reinstalled app launched with Forward+ / Metal and its signature verified. The user's live voyage reached level 2 after 50.1 sailing seconds; [native telemetry](../evidence/camera-49.txt) confirms projection `(0.5285714, 0.39642859)`. The [capture](../evidence/camera-49.png) is obscured by the upgrade menu, so it is runtime evidence rather than a clear boat comparison. No errors were observed in the [runtime log](../evidence/camera-49-runtime.txt). Extended combat, collision and streaming checks were not repeated for this camera adjustment.

## Expanded speed cycle and final framing — 2026-09-10

The speed button cycles ×1 → ×2 → ×3 → ×10 → ×20 → ×1. Each multiplier repeats the existing bounded simulation step; a new voyage still starts at ×1. Orthographic zoom is `0.74 / 1.40`, showing 40% more world along each axis from the original baseline. Boat geometry is 80% larger than its original proportions (about 28.6% larger on screen after zoom), with shared weapon and health-bar scaling. Camera elevation remains 51°. The spawn moved 25 simulation units east for dock clearance.

Debug and Release passed with zero warnings/errors, and macOS export completed without warnings/errors. The reinstalled app launched with Forward+ / Metal and its signature verified. Native captures and paired telemetry confirm [×10](../evidence/speed-x10.png), [×20](../evidence/speed-x20.png), and [wrap to ×1](../evidence/speed-wrap-x1.png). Live play reached level 3; upgrade selection resumed the voyage. The ×20 capture also shows final framing, readable flag and health bar, and hull clearance beside the dock. No runtime errors were observed in the [installed runtime log](../evidence/speed-20-runtime.txt). Earlier [offshore telemetry](../evidence/camera-40-boat-80.txt) records 79.4 active sailing seconds with the final geometry and camera. Extended high-speed combat, collision and streaming stress checks were not repeated.

## Wider view and larger boat — 2026-09-10 (superseded proportions)

Orthographic zoom is 0.70 pixels per simulation unit, down from 0.74: about 5.7% more world coverage along each axis. The shared boat geometry scale is multiplied by 1.15, yielding about 8.8% larger on-screen dimensions after the zoom change. Aimed weapon fittings and the mast-based health-bar position inherit the same scale. The 51° camera elevation is retained.

Debug and Release passed with zero warnings/errors. The macOS export completed without warnings/errors, the reinstalled app launched with Forward+ / Metal, and its signature verified. The [native voyage capture](../evidence/wider-camera-boat.png) and [telemetry](../evidence/wider-camera-boat.txt) verify normal-scale framing, visible flag and health bar, and visual hull clearance beside the dock. This is a presentation-only adjustment; extended combat and collision checks were not repeated.

## Pirate flag and lower camera — 2026-09-10

The camera now sits about 51° above the water (ground foreshortening 0.78, previously 0.84/about 57°), preserving orthographic scale 0.74. All boat variants share a taller mast and larger dark, double-sided skull-and-crossbones flag generated from geometry. The health bar uses the mast's scaled height instead of boat-type-specific cabin heights, keeping it above the flag.

Debug and Release passed with zero warnings/errors. The macOS export completed without warnings/errors; the reinstalled app launched with Forward+ / Metal and its signature verified. No runtime errors were observed. The [native harbor capture](../evidence/pirate-camera-harbor.png) and [telemetry](../evidence/pirate-camera-harbor.txt) show the flag, sail and health bar at normal playing scale with projection `(0.74, 0.5772)`. Source review confirms scenery bounds, menu framing, ground clicks and HUD positions use the shared camera/projection. Native pointer steering and a full combat/streaming replay were not independently verified.

## Wider visible shallows and diffuse beaches — 2026-09-10

Removed the broad transparency mask that erased sections of underwater shoreline. Shelf geometry now scales more generously with island radius, with smooth coastline-length variation bounded to 56–100% of its size-scaled envelope. Inner-water opacity stays visible around the coast; noise affects only the outer fade and seabed appearance. The beach-to-grass transition uses a dedicated matte ground shader with an island-size-scaled blend through dry grass, plus broad, low-contrast variation. Interpolated conservative shore distances preserve the dry-beach reserve.

Debug and Release passed with zero warnings/errors. The macOS export and installed signature check passed; the installed app launched and started a voyage without runtime or shader errors. Native visual checks cover the [small compact island](../evidence/wide-shore-small.png), [reference crescent bay](../evidence/wide-shore-crescent.png), and [large lobed island](../evidence/wide-shore-large.png), with [art runtime](../evidence/wide-shore-art-runtime.txt). Final [installed gameplay](../evidence/wide-shore-gameplay.png), [paired telemetry](../evidence/wide-shore-gameplay.txt), and [runtime log](../evidence/wide-shore-installed-runtime.txt) record the shipped shaders. Collision and world placement are unchanged; extended streaming, all-seed, and stress checks were not repeated.

## Natural shoreline — 2026-09-10 (superseded appearance)

Underwater geometry now uses rounded outward coastline offsets instead of radial enlargement. Seeded low-frequency curves vary width along coastline length, and stable broad shader patches soften the outer edge and deliberately fade some sections out. This avoids a uniformly visible underwater ring without letting concave geometry accidentally squeeze away the shelf. Dry beaches use a smaller seed-varied distance reserve. Full prop footprints, including palm crowns, must fit behind it; undersized props are omitted.

Debug and Release passed with zero warnings/errors. The final macOS export completed without warnings/errors, the installed app launched with Forward+ / Metal, and its signature verified. `build/.gdignore` prevents subsequent exports from importing their own previous app output.

The [exact screenshot island](../evidence/natural-shore-crescent.png) (radius 355.70514, seed 2273309013) was rechecked using B in the native art sample; its [runtime log](../evidence/natural-shore-art-runtime.txt) records the final soft patching and variable width. Earlier offset checks also covered a radius-720 long island. A [fresh installed voyage](../evidence/natural-shore-gameplay.png), [paired telemetry](../evidence/natural-shore-gameplay.txt), and [runtime log](../evidence/natural-shore-installed-runtime.txt) verify the final shader in gameplay. No final runtime errors were observed. World placement and collision geometry are unchanged. Extended shore-collision, encounter-access, chunk-unload/revisit, all-seed, and stress checks were not repeated for this presentation change.

## Pirate ships — 2026-09-10

Debug and Release builds passed with zero warnings/errors. All three boats share the new C# pirate hull, square sail, straw-hat skull emblem, ram figurehead and raised stern weapon mount. No imported gameplay assets. The macOS .NET export completed without warnings/errors after adding its solution file, export preset and ARM texture-import setting. Installed at `~/Applications/Boats n Beasts.app`, signed locally with macOS `codesign`, and verified the bundle signature. The existing save directory is preserved.

Native installed-app play verified Gunboat sailing at normal camera scale, level-up selection, a second Whirlpool fitting on the stern, Cannon rank 3, and pause. The [sailing capture](../evidence/pirate-sailing.png) and [paired telemetry](../evidence/pirate-sailing.txt) show level 6 at 7:22 combat time, 100/100 health, 156.2 active sailing seconds, 16.70 ms mean frame time and 117 draw calls. [Upgrade capture](../evidence/pirate-upgrade.png) and [telemetry](../evidence/pirate-upgrade.txt) show both weapon slots. These are unedited F12 captures from the installed app. Runtime startup and capture logs reported no errors. Aura/Mage and every upgraded fitting combination were source-reviewed; no new runtime sweep or full voyage was performed.

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
