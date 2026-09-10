# Verification

## Required checks

Build Debug and Release with `dotnet build` and `dotnet build -c Release`. For behavior or visual changes, launch with `./run.command` and use ordinary controls. Do not create automated tests, inject game state, or substitute an art sample for gameplay verification.

Check the affected behavior at normal camera scale. For world changes, include shore collision, reachable encounters, chunk unloading/revisits and bounded caches. For combat changes, include pause/resume, progression, pickups and sustained play. Save unedited F12 screenshots with paired telemetry and report runtime errors, measurements and coverage limits. Update the baseline, gaps and evidence below.

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
