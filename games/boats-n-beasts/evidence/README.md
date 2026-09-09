# Native gameplay evidence

## Remove repetitive salvage encounters — 2026-09-09

Unedited native captures from ×1 Cutter voyage seed `1701921431`, with matching TXT telemetry:

- [Home](no-wreck-home.png): treasure and fishing remain; the wreck and its two rocks are absent.
- [Treasure collected](no-wreck-treasure.png): 38 gold, two kills and exactly one collected chest.
- [Former wreck site](no-wreck-passage.png): open water, full hull, 44 gold and eight kills; no salvage reward.
- [Fishing after returning](no-wreck-fishing.png): normal fishing UI, treasure still depleted, 25 loaded chunks.

[Runtime log](no-wreck-runtime.txt). [QUALITY.md](../docs/QUALITY.md) records the checks and limits.

## Gradual 20–25 minute progression — 2026-09-09

Final native Cutter voyage, seed `3937392081`, reaches victory at **22:11**. Captures have paired TXT telemetry. Most of the run uses the built-in ×3 control, returning to ×1 before the boss; no gameplay state is injected.

| Capture | What it records |
| --- | --- |
| [Offshore at 3:16](gradual-offshore.png) | More than three leagues from home, full hull, no early boss and fixed crab/puffer stats. |
| [Pause](gradual-pause.png), [handbook](gradual-handbook.png) | New 22:00 objective; identical combat/director/enemy state across 17 seconds of menu time. |
| [9:38](gradual-middle.png), [14:43](gradual-fifteen.png), [18:26](gradual-late.png) | Earned upgrades, gradual enemy mix and rising population through the voyage. |
| [21:58.96](gradual-before-boss.png) | Still full hull, no Crownclaw or hostile shots; observed population peak 18. |
| [22:10.65](gradual-boss.png) | Crownclaw age about 10.67 seconds, eight escorts, active bombs and boss damage. |
| [22:11 victory](gradual-victory.png) | 22/100 hull, 1,661 kills, enemies/shots cleared and the normal victory menu. |

[Complete final runtime log](gradual-runtime.txt). [QUALITY.md](../docs/QUALITY.md) records the exact timing, performance and coverage limits. This is one successful build, not a claim that every build survives or that the 64-enemy maximum was reached.

## Puffer report: remove backward cannon returns — 2026-09-09

Unedited final-build captures from Cutter voyage seed `3180561041`: [armed puffers at 51.3 seconds](puffer-no-return-armed.png) and [six detonations by 56.5 seconds](puffer-no-return-outcome.png). Each has matching TXT telemetry. The first records three active fuses and no shots; the second records only a friendly cannonball. Boss spawning and bomb counts remain zero in this voyage.

The [runtime log](puffer-no-return-runtime.txt) also contains a preceding voyage; the two captures above identify the focused puffer check. [QUALITY.md](../docs/QUALITY.md) distinguishes observed puffer behavior from the inferred cause of the user's report. The fix ends an isolated cannon hit instead of reversing it back from the monster.

## Giant islands — 2026-09-09

Unedited native samples compare [the previous large size, radius 330](giant-previous-large.png) with [the new maximum, radius 720](giant-compact.png), both compact style 4. Camera and boat scale are identical. The giant layout centers the island, moves the boat aside and hides the harbor/crab; some coast edges extend beyond the normal view.

| Family at radius 720 | Sample |
| --- | --- |
| Compact | [Style 4](giant-compact.png) |
| Long | [Style 6](giant-long.png) |
| Crescent | [Style 1](giant-crescent.png) |
| Lobed | [Style 2](giant-lobed.png) |
| Headland | [Style 12](giant-headland.png) |
| Bean | [Style 32](giant-bean.png) |
| Twin | [Style 33](giant-twin.png) |
| Scalloped | [Style 34](giant-scalloped.png) |

Gameplay PNGs have matching TXT telemetry: [home](giant-title.png), [dock](giant-harbor.png), [644.63-radius island approach](giant-approach.png), [shore contact](giant-contact.png), [49.2-second defeat at the same shore position](giant-defeat.png). These use ordinary Cutter play, seed `1679446102`, with 25 loaded chunks.

Logs: [initial sample](giant-sample-runtime.txt), [sample after stepping-stone correction](giant-final-sample-runtime.txt), [gameplay](giant-gameplay-runtime.txt). Compact, crescent and lobed captures use unchanged geometry from the initial sample; the other five families follow the correction. The sample constructs no Voyage. [QUALITY.md](../docs/QUALITY.md) gives measurements and coverage limits.

## Rounded coasts and eight island families — 2026-09-09

Unedited native captures after the abrupt-line correction. Compare the [previous sharp bay](variety-crescent-330.png) with the [rounded bay](rounded-crescent.png), both style 1 and radius 330. The final curve uses broader guides and continuous transitions.

| Family, radius 330 | Final sample | Additional seed |
| --- | --- | --- |
| Compact | [Style 4](rounded-compact.png) | |
| Long | [Style 6](rounded-long.png) | |
| Crescent | [Style 1](rounded-crescent.png) | [Style 10](rounded-crescent-10.png), [style 11](rounded-crescent-11.png) |
| Lobed | [Style 2](rounded-lobed.png) | |
| Headland | [Style 12](rounded-headland.png) | |
| Bean | [Style 32](rounded-bean.png) | [Style 36](rounded-bean-36.png) |
| Twin | [Style 33](rounded-twin.png) | [Style 41](rounded-twin-41.png) |
| Scalloped | [Style 34](rounded-scalloped.png) | |

Small fitting checks: [crescent, radius 95](rounded-crescent-small.png) and [twin, radius 95](rounded-twin-small.png). Radius-200 versions were also reviewed in the native sample; the [sample log](rounded-sample-runtime.txt) records each profile/size/seed.

Gameplay PNGs have matching TXT telemetry: [home](rounded-title.png), [dock](rounded-harbor.png), [shore contact A](rounded-contact-a.png)/[B](rounded-contact-b.png), [offshore twin](rounded-offshore-twin.png), [large long island](rounded-offshore-large.png), [54.8-second defeat](rounded-defeat.png). [Gameplay log](rounded-gameplay-runtime.txt). [QUALITY.md](../docs/QUALITY.md) gives measurements and coverage limits. The art sample is separate from gameplay and contains no Voyage.

## Distinct island sizes and coastline families — 2026-09-09

Unedited normal-camera native samples compare three radii beside the same boat and harbor. Compact, long and lobed geometry is unchanged from the initial sample build; crescent and headland captures follow their final refinement.

| Profile | Small, radius 95 | Medium, radius 200 | Large, radius 330 |
| --- | --- | --- | --- |
| Compact | [Small](variety-compact-95.png) | [Medium](variety-compact-200.png) | [Large](variety-compact-330.png) |
| Long | [Small](variety-long-95.png) | [Medium](variety-long-200.png) | [Large](variety-long-330.png) |
| Crescent | [Small](variety-crescent-95.png) | [Medium](variety-crescent-200.png) | [Large](variety-crescent-330.png) |
| Lobed | [Small](variety-lobed-95.png) | [Medium](variety-lobed-200.png) | [Large](variety-lobed-330.png) |
| Headland | [Small](variety-headland-95.png) | [Medium](variety-headland-200.png) | [Large](variety-headland-330.png) |

Actual gameplay, with matching TXT telemetry: [home dock](variety-harbor.png), [shore contact A](variety-contact-a.png)/[B](variety-contact-b.png), [open-water streaming](variety-streaming.png), [offshore crescent](variety-offshore-crescent.png), [offshore headland at 57.8 seconds](variety-offshore-headland.png). [QUALITY.md](../docs/QUALITY.md) records measurements and coverage limits.

Logs: [initial sample](variety-sample-runtime.txt), [refined bay/headland sample](variety-final-sample-runtime.txt), [gameplay](variety-gameplay-runtime.txt). The sample constructs no Voyage. Gameplay uses ordinary controls with no state injection.

## Final reef art with shared island shapes — 2026-09-09

Unedited native captures from the final implementation. Gameplay PNGs have matching TXT telemetry.

| Capture | What it establishes |
| --- | --- |
| [Home](island-fitted-title.png), [harbor](island-fitted-harbor.png) | Final shared home-island silhouette, fitted props and accessible starting dock. |
| [Sailing A](island-fitted-sailing-a.png)/[B](island-fitted-sailing-b.png) | Actual movement, changing surf, full Aura hull and 25 loaded chunks. |
| [Shore approach](island-fitted-contact-a.png)/[contact](island-fitted-contact-b.png) | Boat reaches the visible curved shore while steering into land. |
| [Ruin sample](island-fitted-ruin.png), [cliff sample](island-fitted-cliffs.png), [grove sample](island-fitted-grove.png) | Normal-scale native art proof of three compositions on differently sized shared island shapes; no gameplay Voyage. |

Logs: [final gameplay](island-fitted-gameplay-runtime.txt), [final art sample](island-fitted-sample-runtime.txt). These follow the uniform prop-fitting correction. [QUALITY.md](../docs/QUALITY.md) gives precise chronology and limits; the older 62.4-second run below is pre-integration evidence.

## Initial reef art pass, before shared-shape integration — 2026-09-09

The [reference](../docs/island-reference.png) is documentation only. Every image here is an unedited native viewport capture; gameplay PNGs have matching TXT telemetry.

| Capture | What it establishes |
| --- | --- |
| [Baseline](island-baseline.png), [pre-integration home](island-title.png) | Original title framing, before/after coasts, shallows, vegetation, harbor and ruins, before shared island geometry was integrated. |
| [First art sample](island-sample-pass1.png) | Intermediate native proof before the final foam, rock and ruin refinements. |
| [Home sailing](island-home-sailing.png), [shore collision](island-shore-collision.png) | Mage beside the ruin island; steering into land leaves the hull outside its existing collision envelope. |
| [Starting dock](island-dock-access.png), [offshore refit](island-offshore-refit.png) | Home and streamed harbors retain their three offers. Home capture predates final rock/ruin refinements. |
| [Offshore cliffs](island-offshore-variety.png), [palm grove](island-grove.png) | Distinct seeded island compositions in actual combat at the normal camera. |
| [56-second exploration](island-streaming.png), [62.4-second defeat](island-sustained.png) | 25 loaded chunks, bounded scenery, active enemies/projectiles and rolling native frame measurements over 8.4 leagues. |

Logs: [exploration](island-runtime.txt), [final contour guard and home](island-final-contour-runtime.txt). These captures predate integration with shared island shapes, sparse world generation and the newer boss bombs. Final integrated evidence is listed above. [QUALITY.md](../docs/QUALITY.md) records exact measurements, chronology and coverage limits. No automated tests, gameplay state injection, imported art or image compositing.

## Island size and silhouette variation — 2026-09-08

[Before/title](island-shapes-before.png), [final title](island-shapes-title.png) and [fresh title](island-shapes-fresh-title.png) compare the fixed home scene. [Shore contact A](island-shapes-contact-a.png)/[B](island-shapes-contact-b.png) show the boat held at the visible edge. [Larger island](island-shapes-large.png) is visible below the defeat panel in the first route. [Curved offshore island](island-shapes-curved.png) shows the final build’s bean-shaped shore and aligned shallow bands. Same-name TXT reports preserve native positions, radius parameters and performance. [Collision/first route log](island-shapes-runtime.txt), [final build log](island-shapes-final-runtime.txt). Coverage limits are in QUALITY.

## Crownclaw ranged bombs only — 2026-09-08

[Paused flight A](boss-bombs-pause-a.png)/[B](boss-bombs-pause-b.png) preserve identical simulation and bomb flight state. [Dodge/detonation](boss-bombs-dodge.png) shows a red dome behind the boat; [volley complete](boss-bombs-volley-complete.png) reports three explosions and zero blast hits, followed by melee defeat. [Mage flight](boss-bombs-flight.png) and [overlapping domes](boss-bombs-domes.png) show the separate stationary encounter; existing contact-hit invulnerability masks bomb damage. Same-name TXT reports include fixed targets and counters. [Native log](boss-bombs-runtime.txt). See QUALITY for coverage limits.

## Sparse scattered offshore islands — 2026-09-08

[Near offshore](sparse-ocean-near.png), [scattered islands](sparse-ocean-islands.png) and [open-water stretch](sparse-ocean-open.png) follow seed `1762272320` out to `(4428,-890)`. [Fresh seed/title](sparse-ocean-fresh-seed.png) preserves home scenery with a different offshore layout. Each TXT report includes all active island/harbor coordinates and styles, plus streaming and timing measurements. [Final runtime log](sparse-ocean-runtime.txt).

## Weapons idle during fishing — 2026-09-08

[Fishing A](fishing-idle-a.png)/[B](fishing-idle-b.png) show enemies approaching with full health, idle Whirlpool and Aura holding a ready pulse. [After timeout](fishing-attacks-resumed.png) records resumed attacks and kills. Same-name TXT telemetry accompanies each image. [Native log](fishing-idle-runtime.txt).

## Individual monster speeds — 2026-09-08

[Gameplay A](individual-speed-a.png)/[B](individual-speed-b.png) show original crab, puffer and serpent colors. Same-name TXT reports show distinct speed multipliers that stay fixed as enemies move. [Native log](individual-speed-runtime.txt).

## Smooth matching island contours — 2026-09-08

[Before](coast-before.png), [rounded title islands](coast-smooth-title.png) and [gameplay shoreline](coast-smooth-gameplay.png) show the same contour used by sand and both blue bands. Same-name TXT reports accompany each capture. [Native log](coast-smooth-runtime.txt).

## Exposed harbors — 2026-09-08

[Before opening E](harbor-exposed.png) shows damage beside the starting dock. [Harbor menu A](harbor-menu-freeze-a.png)/[B](harbor-menu-freeze-b.png), captured 2.025 seconds apart, have identical simulation telemetry. [After closing](harbor-combat-resumed.png) shows resumed combat and further damage at the same position. Each PNG has a same-name TXT report. [Native log](harbor-exposed-runtime.txt).

## Fishing keeps time running — 2026-09-08

[Fishing A](live-fishing-a.png)/[B](live-fishing-b.png), with paired TXT telemetry, show advancing combat time, moving/spawning enemies and automatic shots while boat position stays fixed. These precede the text correction. [Final UI](live-fishing-ui.png) says “Combat active.” [Timeout](live-fishing-timeout.png) and [manual reel miss](live-fishing-reel.png) return to Sailing. Logs: [simulation check](live-fishing-runtime.txt), [final UI/reel](live-fishing-final-runtime.txt).

## Downward dockside heading — 2026-09-08

[Title](dock-down-title.png) and [voyage start](dock-down-start.png) show the downward-facing boat with a small extra gap beside the dock. Paired TXT reports retain position `(55,-315)` and zero velocity.

## Exploding puffers and swift variants — 2026-09-08

Every capture has same-name TXT telemetry. [Fuse](puffer-fuse.png) and [damage](puffer-damage.png) show an armed puffer and its detonation dealing 28 hull damage (before final dome shading). [Pause A](puffer-pause-a.png)/[B](puffer-pause-b.png) retain the same armed fuse and positions. [Swift fuse](puffer-swift-fuse.png), [swift dodge](puffer-swift-dodge.png) and [final regular dodge/dome](puffer-dome-dodge.png) show two detonations avoided by sailing, with hull and blast-hit count unchanged. Violet regular-monster variants are visible alongside their standard counterparts. Logs: [initial](puffer-runtime.txt), [final](puffer-final-runtime.txt).

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
