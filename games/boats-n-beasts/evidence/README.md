# Native gameplay evidence

## Remove enemy warning lines — 2026-09-08

[Windup](no-warning-windup.png) and [dash](no-warning-dash.png), with same-name TXT telemetry, show puffer/serpent preattack states without warning lines and the subsequent serpent dash. Actual hostile projectiles remain visible. [Runtime log](no-warning-runtime.txt).

## Flat-shaded nautical diorama — 2026-09-08

The [selected reference](../docs/visual-restart/flat-diorama-reference.png) is documentation only. Images below are unedited native captures. Every gameplay PNG has a same-name TXT report.

| Capture | What it establishes |
| --- | --- |
| [Baseline](diorama-baseline.png) | Native pre-restyle water, materials and scenery. |
| [Art sample](diorama-sample-scale.png), [detail](diorama-sample-detail.png) | Generated rock, cottage, palm, boat and crab forms; separate visual scene with no Voyage. Predates only final crystal enlargement/wake correction. |
| [Final gameplay](diorama-gameplay.png), [Crownclaw](diorama-crownclaw.png), [title](diorama-title.png) | Final integrated visual treatment and corrected wakes at actual playing scale. |
| [Gunboat preview](diorama-gunboat-preview.png)/[start](diorama-gunboat-start.png), [Mage preview](diorama-mage-preview.png)/[start](diorama-mage-start.png), [Aura preview](diorama-aura-preview.png)/[start](diorama-aura-start.png) | Same dockside spawn, zero velocity and camera for all three selected boats. |
| [Fade](diorama-fade.png), [five seconds later](diorama-stationary.png), [retry](diorama-retry.png) | No automatic sailing destination or movement; fade preserves scene/camera and retry restores home. |
| [Mage play](diorama-mage-play.png), [Aura play](diorama-aura-play.png) | Homing attacks, Aura combat, refined low serpents, currents and offshore streaming. These precede the final wake-only correction. |
| [Level freeze A](diorama-level-freeze-a.png)/[B](diorama-level-freeze-b.png), [streaming after choice](diorama-streaming.png) | Free upgrade freezes gameplay, then play resumes and streams with 25 active chunks. Precedes final geometry/effect refinements. |
| [Catch](diorama-catch.png), [sale](diorama-sale.png), [purchase](diorama-purchase.png) | Manual successful single reel, direct return to sailing, automatic 14-gold sale and 26-gold Reload purchase. |

Logs: [initial pass](diorama-runtime.txt), [refined game](diorama-final-runtime.txt), [final wakes/Crownclaw](diorama-wakes-runtime.txt), [art sample](diorama-sample-runtime.txt). See [QUALITY.md](../docs/QUALITY.md) for chronology, measured performance and coverage limits. No automated gameplay tests, injected state, image-generated gameplay art or image compositing was used.

## Stationary dockside start — 2026-09-08

[Title](dock-start-title.png) and [start during fade](dock-start-still.png), each with same-name TXT telemetry, show the boat alongside the wooden dock at `(35,-315)`. Position, zero velocity and camera are unchanged when starting; no sailing destination is assigned. This replaces the automatic initial course in the earlier departure captures below.

## Shared title and voyage start — 2026-09-08

Unchanged native PNGs with same-name TXT reports; the reports now include camera position, departure time, menu opacity and the fixed home geography ledger.

| Captures | What they establish |
| --- | --- |
| [Title](departure-title.png) | Real cottage upper-left, island lower-right, Mage to the left; open water behind all menu actions. |
| [Gunboat preview](departure-gunboat-preview.png), [Aura preview](departure-aura-preview.png), [Mage preview](departure-mage-preview.png) | Three different voyage seeds; identical starting position, camera and all nine home places/styles. |
| [Early fade](departure-fade-early.png), [middle](departure-fade-middle.png), [late](departure-fade-late.png) | Boat moves while menu opacity falls; camera and real scenery stay fixed throughout the fade. |
| [Aura override](departure-aura-override.png), [Mage departure](departure-mage-fade.png) | A click overrides Aura's course before the menu fully disappears; Mage starts moving while the menu is still visible. |
| [Gunboat play](departure-gunboat-play.png), [Aura play](departure-aura-play.png) | Normal camera following, combat and free level-up choices after departure. |
| [Retry](departure-retry.png) | Fresh seed and the same starting camera/geography after defeat. Capture is the first retry frame while normal scenery generation is filling its cache. |
| [Home harbor](departure-harbor.png), [shore approach](departure-shore.png) | Actual docking at the new cottage position, three harbor offers, Mage combat and collision along the visible shore. |

[Runtime log](departure-runtime.txt) retains the native session output. Rapid fade captures include PNG-save stalls and are not performance measurements. See [QUALITY.md](../docs/QUALITY.md) for scope and limits. This shared geography replaces the menu-only offsets in the older entry below.

## Clear title backdrop — 2026-09-08

[Clear title](menu-clear-title.png) shows the island lower-right, the boat left and open water behind all menu content. [Sailing](menu-clear-sailing.png) shows normal scenery positions and encounter props restored after Set sail. Both have same-name TXT reports. Return-to-title was also checked natively.

## Title and pause menus — 2026-09-08

[Before](menu-before.png), [final title](menu-title.png), [keyboard focus](menu-title-focus.png), [pause](menu-pause.png), and [resumed sailing](menu-resume.png) are untouched native 1280×800 captures from the menu polish pass. Same-name TXT files retain the runtime state. They show the house clear of the title, consistent code-drawn icons and button styling, and normal play after Resume. Play/boat selection, keyboard handbook access/return and End voyage/title were also exercised directly. Builds and coverage are recorded in QUALITY.md.

## Direction B acceptance — 2026-09-08

These are unchanged native viewport captures and contemporaneous telemetry from Godot 4.7.2 .NET, Forward+ / Metal on Apple M3 Max. The production world is generated by C# meshes and shaders. No image generation, compositing, automated gameplay tests or injected simulation state was used. Timestamped originals are retained locally; descriptive copies below are tracked.

| Native capture | Evidence |
| --- | --- |
| [Baseline](direction-b-baseline.png) | Pre-restart 2D renderer; the ranked starting gaps are in ART_DIRECTION.md. |
| [Sample scale](direction-b-sample-scale.png), [detail](direction-b-sample-detail.png) | Separate native proof with boat, crab, cottage, island and water; no Voyage. Final shared art, camera and lighting; runtime reports 120 FPS / 11 draws. |
| [Final gameplay](direction-b-gameplay.png) | Final integrated native turn, broken curved wake, matte hull, cottage, rocks, turquoise coves, submerged fish and rounded chest. Velocity is nonzero in the paired report. |
| [Harbor world](direction-b-harbor-world.png) | Final submerged-cove geometry before the last foam-only refinement. |
| [Mage play](direction-b-mage-play.png), [Aura play](direction-b-aura-play.png) | Actual selected starter boats: 13 homing-orb casts; Whirlpool combat/pulse and movement. These preceded final rock/cove/foam refinements and are gameplay evidence, not final scenery acceptance images. |
| [Boost held](direction-b-boost-held.png), [released](direction-b-boost-released.png) | Real Shift hold: boost starts 1, charge 38.70, velocity about 601, rapid-fire factor 1.65 at level-up. After release/resume charge returns to 100 and firing factor to 1. |
| [Catch](direction-b-catch.png) | One manual timed reel catches Silver sprat, cargo 1, Sailing mode without a result popup; school depleted. |
| [Sale](direction-b-sale.png), [redock](direction-b-redock.png), [paid upgrade](direction-b-paid-upgrade.png) | Automatic 14-gold sale, no duplicate sale on redocking, then a 26-gold Reload purchase (39 to 13). Three single-category harbor offers. |
| [Level freeze A](direction-b-level-freeze-a.png), [B](direction-b-level-freeze-b.png), [resumed](direction-b-level-resumed.png) | Immediate free choice at sea; all combat fields identical 16 seconds apart. Selection resumed combat with Cannon + Lightning; later defeat records continued clock/kills. |
| [Streaming](direction-b-streaming.png) | Aura reached about two leagues, 62.5 seconds sailing, 15 enemies, 25 active chunks, current riding and treasure collection. |
| [Sustained](direction-b-sustained.png) | Gunboat ran 111.1 seconds, 74 kills, two silver awards; sampled mean 10.27 ms, p95 16.02 ms, p99 16.73 ms. |

Every gameplay PNG above has a same-name TXT report. [Final runtime log](direction-b-runtime.txt) and [sustained runtime log](direction-b-sustained-runtime.txt) retain engine output. The frame measurements use a bounded rolling sample of sailing frames; they are not whole-session GPU benchmarks. Earlier gameplay pairs precede final presentation refinements; simulation is unchanged throughout the Direction B pass. See [QUALITY.md](../docs/QUALITY.md) for coverage limits and [independent critique](../docs/visual-restart/independent-critique.md) for visual acceptance.

## Historical evidence below

The following sections describe earlier builds and sometimes superseded mechanics/renderers. They are retained as history, not the current feature contract.


Captured through the running Godot Compatibility renderer during actual UI play on 2026-09-07. PNGs are unchanged viewport captures; paired TXT files contain the contemporaneous runtime state. No simulation harness, injected game state, image generation, or compositing was used. Raw timestamped captures remain locally ignored; this directory retains a representative set.

| Capture | What it establishes |
| --- | --- |
| `title`, `final-hud` | Final build presentation and measured right-side HUD padding. |
| `fishing-frozen`, `fishing-result` | Combat fields are identical across assisted fishing resolution; cargo/depletion changes. |
| `boost-exhausted`, `boost-recharged` | Empty boost stays exhausted; release allows recharge. |
| `defeat` | Actual defeated run and available restart. |
| `refit` | Harbor economy and a developed weapon build. |
| `boss-fight`, `boss-cleared` | Crownclaw combat, then defeated boss and cleared escort. |
| `depleted-revisit` | Home school remains depleted after its chunk unloaded and reloaded. |
| `victory` | Completed chart, boss defeat, harbor return and victory claim. |
| `endless-crowd` | Same winning voyage continued into deep negative coordinates and crowded combat. |
| `cache-streaming`, `cache-crowd-metrics`, `cache-crowd` | Final scenery cache after 6–14 leagues, including 64 enemies and 85 projectiles. |

Earlier captures precede the final scenery optimization and HUD padding fix. The crowded final-cache capture revealed the clipped status line; `final-hud` shows its corrected measured layout. Full victory was played before the claim button moved into the existing harbor service row; its gameplay callback is unchanged. See [quality notes](../docs/QUALITY.md) for precise coverage and limitations.


### Nautical gameplay follow-up

The `nautical-gameplay-*` PNG/TXT pairs cover normal-play exploration, encounter rewards, mines, Harpoon and Cannon. Read the TXT behavior counters alongside screenshots; a still image cannot show the full movement or projectile path. See `docs/QUALITY.md` for the exact checks and remaining coverage gaps.


## Five-item readability polish

- `polish-equipment-hover`: final procedural icon, rank and hovered description; boat stays at the origin after clicking the icon.
- `polish-boost-emergence`: exhausted boost with readable toggle cue and a puffer mid-emergence (age 0.308 seconds, attack clock 1.258 seconds).
- `polish-boost-recharged`: same voyage after release, full boost restored and cue hidden.
- `polish-weapon-harbor`: Lightning/Harpoon/Cannon preview agrees with all three shop offers.
- `polish-upgrade-harbor`: Reload/Hull/Reach preview agrees with shop, including Hull rank-one price. Captured before the final hover/cue-only fixes.

Each image has its native telemetry partner. Original timestamped captures remain local; no state injection or automated tests were used.


## Settings removal

`no-settings-pause` shows the simplified pause menu. `manual-fishing` and `manual-fishing-timeout` show manual instructions followed by a no-input missed catch, with frozen combat telemetry. All three have native PNG/TXT pairs.

`fixed-boat-harbor` verifies the harbor without a mid-run boat switch.


## Simplified run flow

- `simple-run-victory`: full normal-play boss victory without charts or a harbor claim; Trawler with Cannon 5, Whirlpool 1 and Reload 1.
- `single-reel-catch`: a single timed input catches a 14-gold Silver sprat.
- `automatic-catch-sale`: docking clears cargo and shows the 14-gold receipt.
- `automatic-sale-revisit`: same balance after re-docking; no duplicate sale.
- `no-right-click-steering`: right-click leaves the boat stationary.

Native telemetry accompanies each image. Victory capture precedes only sale-header/report/copy cleanup; the remaining captures use the final implementation.

- `catch-without-popup.png/.txt`: successful Silver sprat, its 14-gold value above the boat, Sailing mode and cargo retained without a result menu.
- `sailing-after-catch.png/.txt`: label cleared; combat clock advanced and steering resumed after the catch.

- `clear-encounter-silhouettes.png/.txt`: gold treasure, grouped fish and broken-mast wreck beside a larger landmark island.
- `banked-level-sailing.png/.txt`: level 2, one waiting upgrade, Sailing mode.
- `harbor-free-refit.png/.txt` and `harbor-refit-complete.png/.txt`: docking offers the banked choice; Harpoon selection returns to Harbor, keeps gold at 6 and clears the pending count while the combat clock stays frozen.
- `readable-combat-no-soak.png/.txt`: level 3 remains Sailing, harpoon rope and hostile coral shots are distinct. These captures precede the final LVL hover hint and barrel-spacing adjustment.

- `three-boat-selection.png/.txt`: Gunboat, Aura and Mage options with the gun boat preview.
- `mage-combat.png/.txt`: native Mage voyage with seven arcane casts and three kills at 17.7 seconds; only Arcane Orbs equipped.

- `concept-style-combat.png/.txt`: revised water, broad beach, shaded creatures and submerged fish. Before the final foam/crystal adjustments.
- `concept-style-motion.png/.txt`: upright Mage crystal, broad shallow shelves and readable combat, following foam refinement. Sparse sand grains and the final Ray body are later build-verified refinements.

- `concept-depth-revision.png/.txt`: intermediate harbor/cabin/shore revision; still below the approved concept. See ART_DIRECTION follow-up gaps.

- `immediate-level-up.png/.txt`: upgrade prompt earned at sea without docking.
- `concept-water-and-refit.png/.txt`: sailing resumed after free Lightning selection; final water/shore and rock-ledge revision.
