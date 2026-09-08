# Quality and verification

## Flat-shaded nautical diorama — 2026-09-08

This is the current visual acceptance record. The [exact selected reference](visual-restart/flat-diorama-reference.png) replaces the earlier Direction B/doodle directions. The native result uses quiet petrol-teal water, simple polygon shallows, warm sand terraces, irregular faceted slate rocks, folded broad palm leaves, solid pitched cottage roofs, matte boat hulls and expressive flat-shaded creatures. Surface grain, fine rock fractures, sand flecks, deck seams, roof tiles and detailed water normals were removed. Low swimming teal serpents have coral fins; Crownclaw retains broad claws, readable eyes and a pale crown; Mage carries a larger upright violet crystal. Existing cream/navy/turquoise HUD and menus fit the new palette and retain their controls.

The [native gameplay capture](../evidence/diorama-gameplay.png), [Crownclaw](../evidence/diorama-crownclaw.png), [title](../evidence/diorama-title.png) and [art sample](../evidence/diorama-sample-scale.png) establish a coherent interpretation at the preserved camera scale. Review rejected regular column-like stone faces, hard-to-see fish and folding wake wedges during creature turns. Final stones have unequal shoulders/caps, submerged fish are clearer, and wakes join along shared banks with smoothed headings and separate trails at reversals. The result retains existing cabin silhouettes and layouts rather than copying the reference’s exact composition. No major unresolved visual gap remains in the reviewed native scenes.

### Native behavior

- Selected and sailed Gunboat, Mage and Aura. Final previews and post-fade captures share `(35,-315)`, zero velocity and camera `(424.86487,-214.90347)`. The initial fade and five-second stationary pair also show no automatic destination or movement. Retry after defeat returns to the same dock. Steering engages normal camera follow; pause/resume and returning to the clear title work.
- Gunboat used Cannon; Mage recorded 10 homing casts; Aura displayed its attack-radius curls and fought offshore. The final run shows crabs, puffers, low serpents, hostile shots and Crownclaw appearing beyond three leagues. No core gameplay files changed.
- Immediate free level-up choices appeared at sea. Captures 2.5 seconds apart retain position, velocity, combat/director clocks, weapon cooldowns, enemies and shots; choosing Hull resumed sailing. Differences between these reports are mouse coordinates, capture timestamp and render statistics only.
- Played a fishing timeout, miss and success. A manual reel at 1.1659 seconds matched cursor 0.4971 to target 0.4365, caught Silver sprat, depleted the school and resumed Sailing without a result popup. Docking automatically sold it for 14 gold. Three boat-upgrade offers remained visible; Reload cost 26 gold, changing 38 to 12.
- Streaming retained 25 active chunks while Gunboat traveled to X=2163, Aura reached about 3.1 leagues and the final Gunboat reached `(3135,-581)` with Crownclaw present. Current riding was recorded. Mesh/trail caches remain bounded; obsolete surface shader files were replaced by `DioramaSurface` and its shader.

### Builds and performance

Debug and Release pass with zero warnings/errors. Native game and art-sample logs are clean. No automated tests or injected state were used. F12 captures and paired reports are indexed in [evidence/README.md](../evidence/README.md).

On Apple M3 Max / Godot 4.7.2 .NET / Metal Forward+ / 4× MSAA, native 1280×800 captures from a 1440×900 logical viewport:

| Run | Sailing time | Frame mean / p95 / p99 |
| --- | --- | --- |
| Initial diorama Gunboat streaming | 64 seconds | 8.37 / 8.33 / 9.09 ms |
| Refined Mage | 50.6 seconds | 8.36 / 8.33 / 9.09 ms |
| Refined Aura offshore | 38.4 seconds | 8.39 / 8.33 / 10.00 ms |
| Final wake/Crownclaw check | 29.2 seconds | 16.74 / 16.67 / 16.67 ms |

The final session ran at roughly 60 FPS; earlier sessions were around 120 FPS. These are observed rolling native frame samples, including capture overhead, not isolated GPU benchmarks or a cross-device guarantee. Rapid fade captures are not used as performance benchmarks.

### Coverage limits

The free-upgrade/64-second streaming checks precede final hull, rock, fish, serpent and wake refinements; final all-boat starts, Mage/Aura play, fishing/sales/purchase and retry followed those shape refinements, and a final Gunboat sailing/Crownclaw pass followed wake smoothing. The art sample predates only the last Mage crystal enlargement and wake correction; current native gameplay uses both. Boss victory, deep-endless crowds, every weapon rank, held boost and every input/device combination were not replayed in this style pass. Their simulation is unchanged; earlier native verification remains historical evidence. No claim of exhaustive visual or balance verification is made.

## Stationary dockside start — 2026-09-08

Supersedes the automatic glide in the shared-start entry below. Every boat now spawns at `(35,-315)`, alongside the outer wooden dock with collision clearance for its bow and stern. Starting a voyage leaves its destination unset. The camera is anchored to the harbor for menu composition and holds there until the player moves; the menu still fades over the same scene.

Native [title](../evidence/dock-start-title.png) and [start](../evidence/dock-start-still.png) captures report identical position `(35,-315)`, zero velocity, no destination and the same camera `(424.86487,-214.90347)`. The boat is beside the dock and clear of both title and boat-selection panels. Subsequent live steering moved the boat and engaged camera follow. The focused capture verifies the stationary start; a prolonged input-free idle was not separately recorded. Debug/Release pass with zero warnings/errors and the native log is clean. No automated tests or injected state.

## Shared title and voyage start — 2026-09-08

This replaces the menu-only layout described in the next two historical entries. `StartingArea` owns nine fixed places across the central 3×3 chunks. The title displays their real positions, including fish and encounter props; all central menu content remains over open water. New voyages and retries retain that geography and its styles while choosing fresh offshore seeds. Set sail retains the selected preview voyage and native meshes, fades the input-transparent menu over 0.65 seconds, and begins a short course toward `(0,-150)`. The camera holds through the fade, then eases into normal following. Returning to the title clears any old sailing destination.

Native input selected and sailed Gunboat, Aura and Mage. Their preview captures have different seeds (3195476677, 3129283324, 1095085161), the same boat position `(0,0)`, identical home place/style ledgers and camera `(428.1081,-217.18147)`. Gunboat's early/middle/late fade captures retain that camera exactly while opacity falls 0.850 → 0.482 → 0.046 and the boat moves forward. Aura accepted a real click destination while the fading menu was still present. Mage also began moving before its fade finished. Normal following subsequently centered the boat; the unsteered Gunboat glide settled near `(0,-154)`.

Gunboat and Aura reached immediate free level-up choices at sea; selecting upgrades resumed play. Mage fired homing orbs, retried after defeat at the same start with a new seed, docked beside the visible home cottage and opened its three boat-upgrade offers. Sailing toward the cottage kept the hull outside the island and slid it along shore. Pause, resume and return to the clear title were exercised. All these runs retained 25 active chunks. [Native captures and telemetry](../evidence/README.md) document the checks.

Debug/Release builds pass with zero warnings/errors; the native log has no runtime errors or warnings. No automated tests or injected state were used. Close-spaced F12 captures stall rendering while PNGs are saved, so their frame percentiles are not a transition-performance benchmark. A separate 31.8-second Mage run reports mean 8.59 ms / p95 9.68 ms / p99 11.88 ms on the reviewed M3 Max. This focused pass did not repeat fishing rewards, boost, boss victory or deep exploration; those mechanics are unchanged and earlier native verification remains below. Offshore random generation was reviewed in code; cross-seed native comparison covered the fixed home region.

## Clear title backdrop — 2026-09-08

The menu-only composition places the lower island at 79% viewport width / 84% height and the boat to the left. The upper rock moves right; random neighboring scenery and encounter props are excluded from the title backdrop so all logo/button bounds have open water behind them. Home scenery generation, collision and gameplay positions are unchanged. Native verification covered the [clear title](../evidence/menu-clear-title.png), boat selection, [restored sailing scenery and encounters](../evidence/menu-clear-sailing.png), and returning to the title after ending a voyage. Both captures have paired TXT telemetry. Debug/Release pass with zero warnings/errors; native log clean. No automated tests or injected state.

## Title and pause polish — 2026-09-08

The menu-only camera frames the home harbor at 22% of viewport width / 31% of viewport height (water-plane anchor), leaving the dimensional cottage clear of the centered title. Sailing camera scale/projection and all simulation code remain unchanged. Title and pause actions share native C# buttons with inset borders, subtle depth, turquoise primary fill, gold keyboard-focus outline and six code-drawn nautical icons. Labels, progression visibility and callbacks are retained.

Verified in the normal 1280×800 native window: house/title separation; all title buttons and pause captions fit; hover/focus styling; Play to boat selection; Tab/Return to handbook and back; Resume to live sailing; End voyage back to the title. Debug and Release pass with zero warnings/errors; the native runtime log is clean. No automated tests or injected state. [Before](../evidence/menu-before.png), [title](../evidence/menu-title.png), [focus](../evidence/menu-title-focus.png), [pause](../evidence/menu-pause.png) and [resumed sailing](../evidence/menu-resume.png) have same-name telemetry partners. Existing Unlock/Quests/Shop placeholder callbacks remain unchanged; no progression functionality was added. Other window sizes were not separately exercised in this focused pass.

## Direction B native acceptance — 2026-09-08

This section records the Direction B renderer acceptance before the shared-start follow-up above. The historical entries below include removed mechanics and the old 2D renderer; they do not override [ART_DIRECTION.md](ART_DIRECTION.md) or the current README.

### Visual result

The native world now uses generated 3D meshes, a shared orthographic camera, warm sun/cool ambient light, soft shadows and matte materials. Petrol water, irregular turquoise coves, warm sand, broad beveled rock masses, clustered palms, arched cottages, rounded hulls/creatures and upright Mage crystal establish a coherent tactile Direction B treatment at gameplay scale. Position-history wakes curve and break into tapered foam; fish remain submerged without overhead icons. The reference is never loaded as a gameplay asset.

Baseline, sample and integrated captures are linked in [the evidence index](../evidence/README.md). Iteration rejected washed-out linear vertex colors, a glaring sea, glowing shelf rims, repeated stone dots, stacked cube rocks, pointed mountain caps, dry cove tokens and overly regular wake rails. The final normal-scale turn resolves those issues. Main owns the final comparison; the independent review accepts the normal-scale native treatment with no major unresolved gaps.

### Actual gameplay verification

- Selected and sailed Gunboat, Aura and Mage. Cannon ricochets, homing orbs (13 casts in the Mage capture), Whirlpool/pulse, Lightning, monster emergence, puffer projectiles and serpent dashes were observed. Boat health labels remain above the 3D silhouettes.
- Click steering, stopping, turns, shore collision and current riding were played. With explicit user authorization, a bounded native Shift key-down/key-up script verified held boost through the real OS input path: charge fell to 38.70, velocity reached about 601 and Gunboat firing factor was 1.65. The script released Shift; subsequent play showed charge 100 and factor 1. Ordinary UI actions used computer-use input. No simulation state was injected.
- Free level-up choices appeared immediately at sea. Final-build captures 16 seconds apart preserve position, clock, director state, cooldowns, enemies and shots exactly. Selecting Lightning resumed combat with two weapons; no harbor was required. Subsequent choices respected the occupied slots.
- Manual fishing miss, timeout and success were played. The successful single reel at 1.079 seconds matched cursor 0.604 to target 0.612, caught Silver sprat, depleted the school and resumed Sailing without a result popup. Docking automatically sold it for 14 gold; redocking sold nothing again. A 26-gold Reload purchase changed 39 gold to 13, from three boat-upgrade offers.
- Streaming stayed at 25 active chunks while traveling about two leagues; the Aura run reached 62.5 seconds with 15 enemies and a peak of 12 shots. Current riding and treasure depletion were recorded. A Gunboat run lasted 111.1 seconds, reached level 4 / 74 kills and awarded two silver; saved silver survived later voyages.
- Diff review against the pre-restart baseline confirms no changes to `source/core`: generation, collision, progression, two-slot capacity, single-benefit upgrades, one-cast schools, unlimited catches, automatic sales and scarce randomized persistent silver retain their implementation. The Godot adapter remains read-only with respect to visual synchronization.

### Builds, errors and performance

Debug and Release builds pass with zero warnings/errors. Final native logs contain no runtime/shader errors or warnings. No automated tests were created or run, following OBJECTIVE.md.

Measured on Apple M3 Max, Godot 4.7.2 .NET, Metal Forward+, 1280×800 window (1440×900 logical viewport), 4× MSAA:

| Native run | Sailing duration | Sample mean / p95 / p99 |
| --- | --- | --- |
| Gunboat sustained | 111.1 seconds | 10.27 / 16.02 / 16.73 ms |
| Aura exploration | 62.5 seconds | 8.89 / 11.11 / 15.33 ms |
| Final foam turn | 9.9 seconds | 8.84 / 11.11 / 15.40 ms |

These support smooth 60 FPS on the reviewed machine. F12 statistics use a bounded rolling sample of sailing frames (up to 7,200, dropping the oldest 3,600), not the entire run or an isolated GPU benchmark. The final sample reports 120 FPS and 11 draw calls. Visible scenery is bounded and generated at most one incoming place per frame ahead of the camera; dead actors/trails are removed and actor variant caches clear on voyage reset.

### Coverage limits

The longest runs and all-boat combat captures precede the final cove/foam refinements; final native sample, steering turn, immediate upgrade freeze/resume and clean runtime checks followed integration. A fresh boss victory, every six-weapon/rank combination, very deep endless crowds, focus-loss pause and every device/input combination were not replayed under the new renderer. Historical boss/crowd evidence below belongs to older presentation and is not claimed as final-renderer proof. Infinite coordinate independence and very long-term memory behavior are structurally reviewed rather than exhaustively established by this session. Performance on other GPUs is unmeasured. These are explicit coverage limits; no known blocking visual or gameplay defect remains.

## Historical verification log


Completed through C# builds, direct game-window interaction, native screenshots and sustained gameplay. No automated tests or scripted state injection were created or used. Representative evidence is indexed in [evidence/README.md](../evidence/README.md).

## Resolved quality gaps

- **Presentation:** original shaded boat/island/creature geometry, animated water, wakes, tells, impacts and readable HUD. Distinct orange Cutter, teal Trawler, crab/puffer/serpent/ray silhouettes and Crownclaw. Handbook and harbor layouts fit the viewport. Final right-side status panel measures its text so larger distance/coin values retain padding.
- **Sailing:** event-coordinate steering, click-to-sail stopping, continuous mouse helm, boost and exhaustion/rearming, capsule-shaped hull clearance, safe harbor boundary, pause and modal input protection. Cannon turret, twin barrels and muzzle locations agree with firing; broadside effect and damage use the same sector angle.
- **Boats and builds:** Cutter Slipstream grants rapid fire through boost; Trawler Bulwark charges defensively, clears shots and soaks enemies. Both can install all six weapons. Simple seeded three-choice ranks/stat upgrades replace complex progression. Actual runs used ranged, aura and close attacks with and without harpoon synergies.
- **Enemies and pacing:** four ordinary behaviors, visible dash/shot tells, consistent obstacle avoidance, distance-based credit/population tuning and short lulls. Boss placement retries if obstructed. Boss escort target is eight; defeating it disperses remaining enemies and suspends spawning until endless continuation.
- **Fishing and economy:** cancel, failed casts, assisted successful catches, finite school supply, selling, repairs, weapon/stat refits and boat swaps. Frozen-state captures preserve combat clock, director state, boost, ability, cooldowns, every enemy field and every projectile position/lifetime across the catch result. Cast cancellation cannot reroll rewards.
- **World:** seed-coordinate-local generation reviewed; live seeds 73919 and 4821, travel in positive/negative coordinates, chunk unloading and depleted-school revisit. Active world remains 25 chunks. Scenery retains only loaded places and resets on new voyages; runtime creature strips are fixed in number. Exploration/depletion history intentionally grows with visited places.
- **Run structure:** completed three offshore school charts, defeated Crownclaw, returned safely, claimed victory, continued endless, docked again without a second claim, then explored deep negative coordinates. Defeat and same-seed retry were played separately. Win count persisted once.
- **Menus/settings:** title and boat selection, invalid seed disabling, handbook, pause/resume, harbor tabs, upgrade choices, defeat/retry, victory/endless and fullscreen toggle observed. Assisted fishing and toggle boost settings persist and were restored off after review.
- **Delivery:** launcher build/import/runtime verified, Debug and Release compile with zero warnings/errors. Original art only; no audio, external visual assets or automated tests. Research provenance separates recovered arithmetic from original tuning.

## Live run evidence

Seed 73919 Cutter reached level 3 with cannon/scatter/mortar, caught an offshore chart, sold fish, repaired from 21 hull and switched to Trawler with aura. A separate Trawler build reached level 8 and killed the boss with cannon3/mortar3/coil3/aura2/scatter2 and no harpoon; its failed harbor return exposed the escort problem that was then fixed.

The subsequent successful Trawler voyage used cannon3/harpoon2/coil2/aura1/scatter1, with no mortar. `victory` records 49 kills, three charts, 173 coins and 110/180 hull. `depleted-revisit` records the empty home school after returning from offshore unloaded chunks. Endless continuation reached X=-11,933, 246 seconds of actual sailing, and peaks of 60 enemies/68 projectiles before the final scenery optimization.

The final-cache seed 4821 Trawler run reached X=-13,454, 95.4 seconds of actual sailing and 64 enemies/85 current projectiles. It held 25 active chunks and nine scenery cache entries after sustained chunk churn. Mean frame time was **9.62 ms**, p95 **12.50 ms**, p99 **12.96 ms**; the capture reported engine 83 FPS, simulation average 0.313 ms and draw submission average 2.212 ms. The subsequent unobstructed capture reached 14.25 leagues. These are observed local runtime measurements, not a hardware-independent guarantee or isolated GPU benchmark. The earlier 60-enemy run measured 17.60 ms mean before scenery caching.

## Verification limits

- Normal fishing misses, failure and cancel were observed. Successful catches in the full runs used the explicitly labeled assisted setting, which calls the same reel/resolution logic. Default manual timing accessibility was not independently established through the latency of remote UI control.
- The focus-out auto-pause hook is implemented, but the available UI interactions did not conclusively produce an actual application-focus-loss event. Escape pause/resume was verified; focus-out behavior remains unverified.
- The complete victory run preceded the final scenery cache and the claim button's move into the harbor service row. The unchanged victory callback was fully played; normal harbor sizing and the final renderer were subsequently checked. The HUD padding fix was checked in a fresh native viewport after the dense run exposed clipping.
- Coordinate-order independence was checked structurally and through revisits, not exhaustively across the infinite world. No claim of exhaustive balance or every keyboard/device combination is made.

No known blocking gameplay defect remains from this review. These limits are coverage gaps, not substituted test results.

## Speed control follow-up — 2026-09-08

Added a subtle top-right ×1/×2/×3 cycle. Each frame repeats bounded simulation steps so movement, combat, fishing and visual effects share the selected game-time rate without increasing collision step size. Menu interaction and performance measurements remain in real time; a new voyage resets to ×1.

Debug/Release builds and direct UI checks pass. Native `speed-x2`, `speed-x3-start/end`, and `speed-x1` evidence records the full cycle without moving the boat. At ×3, combat time advanced from 1.4497 to 5.8248 during approximately 1.4 seconds of actual sailing. The two `speed-paused` captures, eleven seconds apart, retain identical combat state at ×3. `speed-x3.png` shows the control and compass spacing. No automated tests were added.

## Simplified HUD follow-up — 2026-09-08

Removed the top-left title/boat/status panel. Experience now fills an eight-pixel bar at the top edge with a compact level label below it; hull is a 96×8 red bar positioned above the boat through the same world-to-screen transform. Removed the replaced corner health/boost/ability readouts and bottom experience bar. Debug and Release builds pass with zero warnings/errors. The rebuilt title was observed; sailing screenshot verification was interrupted by concurrent user interaction, so no new in-game visual verification is claimed.

## Centered inventory follow-up — 2026-09-08

Acquired weapons and stat upgrades now share a compact, centered bottom row with ranks; unowned slots are omitted. Removed the permanent region heading, bottom control legend and objective sentence. The current objective appears in the pause menu; contextual interaction prompts and the opening controls toast remain. Direct runtime observation verified the two starting items centered, the red health bar above the boat, top experience bar, and pause objective fitting the panel. `evidence/minimal-hud.png` records the native sailing view. Debug/Release builds pass; no automated tests were added.

## Run counters and silver — 2026-09-08

Added compact top-left combat time, persistent silver, run gold and monster-kill counters. Removed duplicate gold from the top-right distance panel and moved the small level label to the top center. Every kill grants one silver; only newly observed kills are credited, and the balance is saved immediately. New voyages reset gold/time/kills while preserving silver. Silver spending is intentionally deferred at the user’s request.

Direct UI play earned 12 silver from 12 kills (`silver-earned.txt`). Relaunch showed 12 saved silver on the title screen; a new voyage retained 12 silver with 20 starting gold, zero kills and a fresh timer (`run-counters` evidence). Debug and Release builds pass with zero warnings/errors. No automated tests were added.

## Scarcer silver follow-up — 2026-09-08

Reduced silver awards to one per ten kills in each voyage. Integer milestone accounting credits every crossed threshold once, including multiple kills in a frame. Existing saved silver is retained; incomplete ten-kill groups reset on a new voyage. Focused build and code review validate this arithmetic change; no new live drop-rate playthrough or automated tests were performed.

## Horizontal icon counters — 2026-09-08

Replaced the vertical text labels with a single compact horizontal row of original code-drawn clock, silver hexagonal coin, gold round coin and skull icons beside numeric values. Row width follows measured values. Direct native runtime review verified spacing, icon readability and retained balances (`horizontal-counters` evidence). Debug/Release builds pass; no image assets or automated tests were added.

## Randomized scarce silver — 2026-09-08

Replaced the ten-kill milestones with a core-owned random 45–90 combat-second eligibility gate; the next actual kill awards one silver and schedules a new interval from that award. A separate per-voyage random generator leaves world/combat/build/fishing randomness untouched. Presentation saves only newly earned silver, preserving existing balances. Pausing/fishing freezes the gate with CombatTime; no catch-up rewards accumulate.

Inspected local Megabonk IL2CPP metadata and native code: ordinary silver uses a time gate and 60/SilverIncreaseMultiplier interval, not a per-kill probability. The random interval here is explicitly custom tuning; RESEARCH.md and the new disassembly excerpt document the distinction.

Native play observations: initial eligibility 74.50001 seconds with zero earned silver. At 12 kills the visible balance remained 12. Final capture at 113.7367 combat seconds and 38 kills records one awarded silver (saved total 13), with next eligibility 134.96675. These demonstrate removal of fixed milestones and rescheduling; no claim of statistical distribution testing or a second drop in this run. The user also controlled the game during this review. Evidence: random-silver-start/result. Debug/Release builds pass; no automated tests were added.

## Minimal nautical chart — 2026-09-08

Top-right now contains only LVL and the map; removed distance/cargo/chart readouts and moved the speed control beneath the top-left counters. Replaced radar styling with code-drawn parchment, compass rose, shoreline polygons, harbor anchors, fishing wave marks and a rotating player arrow. North stays fixed; depleted schools remain hidden, and distant home/boss bearings stay within the chart rim without an external legend. Direct native runtime observation verified spacing and visible chart symbols (`nautical-chart` evidence). Debug/Release builds pass. No external assets or automated tests were added.

## Clear weapons and upgrades — 2026-09-08

Shortened names to Cannon, Harpoon, Bomb, Lightning, Whirlpool and Blast; boat upgrades are Hull, Speed, Reload and Reach. Each choice now has one short role description and a next-level benefit, including exact pierce/chain counts and the cannon’s second-barrel milestone. Harbor and bottom inventory use the same names. Retained the six distinct automatic attack behaviors and simple rank progression.

Soaked damage is now a shared +50% for Bomb, Lightning and Blast (Lightning changed from +80%, Blast from +35%, Bomb unchanged). This is a deliberate simplification and balance adjustment. Cards and harbor both explain the shared rule. Debug/Release builds and source checks passed; direct UI play verified the upgrade cards, acquiring Whirlpool, and the full harbor list fitting on screen. Native evidence: clear-upgrades and clear-refits. Long-run balance after the multiplier change was not replayed; no automated tests were added. Fullscreen was used to refresh a stale viewport during review and restored to windowed afterward.

## Minimal home and progressive menu — 2026-09-08

Home now shows the game title and Play, plus inert Unlock/Quests/Shop buttons after 1/2/3 ended voyages. No hidden-button gaps or seed/boat/settings panels remain on home. Play opens a separate boat-selection view with ability details, seed, Set Sail and Back. Settings/handbook stay in pause.

A saved finished_runs counter increments once per voyage on defeat, victory or explicit return to title. A separate per-voyage guard prevents duplicate increments at repeated result/menu visits and after endless continuation. Opening/backing out of selection does not count. Existing saves migrate from recorded wins, since historic losses were not stored.

Actual UI checks: existing save migrated to one run and showed Play/Unlock; starting and ending a voyage revealed Quests at two; selection Back kept the count unchanged; choosing Trawler then ending another voyage revealed Shop at three. Saved config confirmed three finished runs with prior win/silver values preserved. Placeholder callbacks have no side effects. Native home-one-run, boat-selection, home-two-runs and home-three-runs captures record the flow. Zero-run hiding and duplicate-result guards were reviewed in code, not through a reset of the user’s save. Debug/Release builds pass; no automated tests were added.

## Minimal single-use fishing spots — 2026-09-08

Removed the overhead hook and reduced each school to a tight bright turquoise ripple, one fading outer ripple and three cream fish silhouettes. Each school now allows one cast, consumed when casting begins; success, failure and cancellation cannot retry it. Active fishing retains its water marker until the attempt ends. Depletion remains stored across chunk unloading, and depleted map markers remain hidden. The three-reel timing minigame is unchanged.

Debug/Release builds pass. Live review saw the new marker and entered fishing; the user also controlled the game during this run. The final state has one catch, depletion 0:0:1=1, and the boat directly over the home school at (171,180). Pressing E stayed in Sailing and displayed the no-school prompt, confirming no second cast after the successful attempt. Evidence: fishing-marker and single-use-school. Cancellation/failure consumption was checked structurally at cast start rather than independently replayed. Windowed mode was restored after viewport review. No automated tests were added.

## Single-effect boat upgrades — 2026-09-08

Hull now increases maximum health by 25 without healing current health. The card and harbor copy state only “+25 max health.” Speed, Reload and Reach each already change one stat; Reach copy is shortened to “+15% attack area.” Repairs remain separate. Focused code review confirms the Hull branch no longer writes Health. Debug/Release builds pass; no new live purchase check or automated tests were performed.


## Harbor stock and weapon capacity — 2026-09-08

Harbors now have three deterministic offers from one category, with no category toggle or reroll on revisit. The purchase method enforces local stock. Runs start with one signature weapon and two total weapon slots. Paid and free acquisitions share the same capacity guard; owned weapons remain upgradeable at capacity. The constructor accepts zero to three future permanent slot upgrades (two to five slots); the shop remains a placeholder. Debug build and diff checks passed. Live harbor purchases and one-weapon combat balance were not playtested in this change.


## Compact nautical menus — 2026-09-08

Unified panel/button palette, smaller heading hierarchy, centered boat selection, three equal harbor/level-up cards, original line symbols, gold purchase controls, keyboard card outlines, subtle hover scale and purchase pulse. Reduced motion disables both animations. Corrected the stale retry label after randomized runs. Debug and Release builds and diff checks passed. Live UI verified title, Play, boat selection, Set sail, navigation to home harbor and the three-card layout at 640×432. Exact stat copy was corrected after that visual review. Purchase pulse and level-up cards were reviewed in code but not exercised in this pass. The launch script's headless import crashed on editor shutdown; launching the built game directly succeeded without runtime errors.


## Nautical concept art pass — 2026-09-08

Reworked sea shader, shoreline shelves/beaches, rock masses and lighthouse base; cream/wood boats with conditional cannon mount and continuous turquoise wakes; simpler broad monster planes, coral crab pincers, ochre puffers, continuous teal serpent body and dark teal rays with cream wing accents; layered fishing ripples. This is a procedural interpretation of the approved concept, retaining the game's top-down camera and existing collision/interaction bounds. No generated bitmap is shipped as game art.

Debug and Release builds and diff checks passed. Live checks covered both boat previews, sailing/wake, island and harbor scenery, crab/puffer combat, fishing marker and casting, and serpent animation in the title scene. Curated evidence: `evidence/nautical-art-sailing.png/.txt` and `evidence/nautical-art-puffers.png/.txt`. One final-build sample measured 16.69 ms mean frame time, 16.67 ms p95 at 60 FPS, 25 chunks, 5 cached scenery textures and 1.102 ms draw submission. No runtime errors observed. Ray and boss live combat, long-run performance and full victory were not replayed; mechanics were not changed.


## Wider camera, coves and fishing spots — 2026-09-08

Implemented 0.74× camera zoom and 0.84 ground foreshortening as a shared 2D projection, not a perspective 3D camera. Rendering/culling and water sampling use inverse-projected viewport bounds; click-to-sail and continuous mouse steering use the inverse transform. HUD remains screen-sized with a smaller boat health bar. The wider view remains inside the existing 5×5 loaded-chunk region at the configured aspect ratio.

Island outlines now use smooth seeded lobes instead of per-vertex jitter, with an offset raised bank, varied rocks, an open beach and loose shore stones. Fishing rings became irregular broken arcs with small pointed fish; single-use behavior is unchanged. Debug/Release builds and diff checks passed. Live verified wide view, click navigation to a fishing spot, cast start/frozen combat, navigation back to the harbor and successful docking. Evidence `wide-camera-shore` and `wide-camera-catch` PNG/TXT pairs preserve the projected view; the latter capture occurred on the catch result after the cast timed out. Final sailing sample: 16.70 ms mean / 16.67 ms p95 at 60 FPS, 13 cached scenery entries, 1.065 ms draw submission. No runtime errors observed. Continuous mouse steering was checked structurally, not separately played; long-run/boss balance was not replayed.


## Movement, nautical weapons and sea encounters — 2026-09-08

Implemented responsive bow steering with short hull drift and release damping; 2.05× boost with an 8-unit burst cost, acceleration kick and speed-weighted wakes. Existing fuel exhaustion/release behavior, collision capsule, camera projection and pause/fishing freezes remain in use. Currents add bounded directional flow and remain navigable against the flow.

Replaced Bomb with trailing Mines and Blast with Broadside, keeping the six indices and two-slot limit. Mines arm after 0.5 seconds, expire after 10 and cap at eight; proximity triggers area damage. Broadside emits three projectiles from each side and automatically aims within its side arcs. A first live pass exposed overly demanding fixed angles; limited side aiming resolved that issue. Cannon ricochets consume a finite bounce budget, exclude previously hit enemies and reflect from solid shore/rock normals. Harpoon applies a short collision-aware pull, reduced to 25% on the boss, plus soak. UI, models and descriptions match the changes. Boat selection now rebuilds its preview loadout when changing boat.

Treasure, current and wreck placement uses a separate coordinate-local RNG. Home waters contain one of each; further encounters vary. Wrecks sit between rocks; treasure and wrecks auto-award run gold once, using sparse depletion that survives chunk regeneration. Non-solid encounters do not enter collision/avoidance or scenery baking. Chart symbols hide collected rewards.

Validation: Debug and Release builds and diff checks passed. Actual UI play acquired Mines, Harpoon and Cannon through level-up choices, with Broadside on the Cutter. Native evidence recorded four mine drops/four explosions, four harpoon pulls, six cannon ricochets, ten Broadside salvos in the Harpoon run and 23 in the Cannon run. A Trawler run recorded one boost start, 3.118 seconds riding a current and two treasure collections. The Harpoon run recorded two wreck salvages; rewards disappeared from the water and chart. A longer final-build sample reached over 10,000 sailed world units with 25 streamed chunks, 20 enemies and 28 cached scenery entries, with 8.39 ms mean / 8.33 ms p95 frame time; no runtime errors observed.

Curated native screenshot/telemetry pairs: `nautical-gameplay-mines-current`, `nautical-gameplay-harpoon-salvage`, `nautical-gameplay-cannon`, `nautical-gameplay-exploration`. The Cannon capture was taken on defeat after six ricochets; it is behavioral telemetry, not a screenshot of a single bounce in flight. Restored hold-to-boost and fullscreen preferences after UI verification. No automated tests or injected game state were used.

Remaining balance/coverage gaps: full victory and prolonged high-tier balance were not replayed; rock-only ricochets, boss pull resistance, eight-mine saturation and reward collection after unloading/reloading were reviewed in code rather than isolated in live play. Existing procedural placement and depletion ownership are retained.


## Five-item readability polish — 2026-09-08

Implemented conditional boost charge/exhaustion feedback, a saved one-time Bulwark explanation, 0.45-second monster emergence with movement/contact/attack updates delayed until emergence completes, procedural bottom equipment symbols with rank badges and hover descriptions, and chart harbor category symbols with fixed-stock previews. Preview and actual store share the same stock function; generation, offer count/category and weapon capacity are unchanged.

Debug and Release builds and diff checks pass. Actual play covered windowed and fullscreen layouts, acquisition of Lightning and Hull alongside Whirlpool, hover details without click-to-sail, a complete boost depletion/recharge cycle, recurring Bulwark pulses without repeated banners, and both harbor categories. Weapon stock Lightning/Harpoon/Cannon and boat stock Reload/Hull/Reach matched their previews and actual shops, including Hull's updated 48-gold price after leveling. A native screenshot shows an emerging puffer at age 0.308 seconds with an attack clock of 1.258 seconds; behavior code delays movement/contact/attack-clock updates until 0.45 seconds. Bulwark's tutorial flag was verified saved and remained true after relaunch.

Live review found weak exhaustion-text contrast over land and hover coordinates inconsistent with the scaled native window. Fixed the cue with a small navy backing and coral empty arc, used viewport input-event coordinates for hover, and consumed equipment clicks so inspecting gear does not steer the boat. Final captures verify the corrections.

Curated PNG/TXT pairs: `polish-equipment-hover`, `polish-boost-emergence`, `polish-boost-recharged`, `polish-weapon-harbor`, `polish-upgrade-harbor`. Boost telemetry goes from 0 to 100 after releasing; the full-charge capture has no boost cue. The upgrade-harbor capture predates only the final hover-coordinate/cue-contrast fixes; stock logic was unchanged. Game left at title with hold boost restored; the user's assisted-fishing and window preferences were preserved. No automated tests or injected game state. This is a focused polish verification, not a new full-victory or high-tier balance validation.


## Settings removal — 2026-09-08

Removed the Settings screen/entry point, fullscreen preference and F11 handler, reduced-motion branches, boost latch/toggle preference, and assisted-reel mode. Normal animation and Space/Shift hold-to-boost are now direct behavior. The existing project defaults provide a standard resizable window. Updated README and handbook copy; historical entries above describe earlier versions.

Debug/Release builds and diff checks passed. Actual UI verified all previously unlocked title entries and 17 silver, the three-button pause menu without Settings, sailing, manual fishing and its no-input timeout. Combat clock stayed at 6.5174108 throughout fishing/result. The existing save had assisted_fishing=true, so this also verifies old preference values no longer activate optional behavior. Hold boost uses the existing physical-key-down polling directly; the UI tool's short press did not register a simulation boost, so sustained hold behavior was reviewed in code rather than claimed as a new live hold test.

A normal end-voyage save retained best_kills=174, wins=1, silver=17 and bulwark_explained=true, incremented finished_runs from 15 to 16, and removed obsolete display/accessibility sections. The legacy settings.cfg path remains for compatibility; no save reset. Native evidence: no-settings-pause, manual-fishing, manual-fishing-timeout PNG/TXT pairs. No automated tests or injected game state. Game left at title.


## Fixed boat per voyage — 2026-09-08

Removed the harbor switch button and SwitchBoat method; Voyage.Boat is now get-only and assigned at construction. Updated current handbook/README copy. Debug build passes; live UI selected Cutter, sailed to harbor and confirmed only Sell/Repair plus the existing three offers and exit. Victory claim remains conditional as before. Evidence: fixed-boat-harbor PNG/TXT. No automated tests.


## Simplified run flow — 2026-09-08

Docking automatically sells all held catches once and clears cargo. Removed the manual Sell action; a concise receipt in the harbor header remains visible behind modal shading. Re-docking resets the receipt to zero and awards nothing further. Repairs and the three fixed offers are unchanged.

Fishing is one manual timed reel, with an eight-second timeout; a miss ends the cast. Removed hit/miss counters, reel cooldown and chart rewards. Combat still freezes, including the result. Removed chart prerequisites and the return/claim-victory step: sailing beyond three leagues spawns the Crownclaw, and killing it enters Victory immediately. Victory takes priority over a simultaneous level-up; the current win is recorded once and optional endless exploration remains. Start, pause, handbook and result copy use the new objective. Removed right-click helm state, input handling, toasts and the unused inverse-direction helper. Boat choice, WASD/arrows, click-to-sail, hold boost, weapon capacity and stock invariants remain.

Validation: Debug/Release builds and diff checks pass; no automated tests or injected state. Full live run: Trawler, Cannon 5, Whirlpool 1, Reload 1, 171 kills, 222.386 simulated seconds at mixed x1/x3, 433 gold and 15.5/155 hull at immediate Victory, with enemies/shots cleared. No chart collection or harbor claim. This capture predates only sale-header/capture-report/copy cleanup, not a change to combat or victory behavior.

Final build: one manual reel at 2.3166 seconds, cursor 0.48696 vs target 0.59450 (band 0.14), caught a Silver sprat worth 14. Docking cleared cargo 1→0, reported last sale 14 and increased gold from 21 to 36 (14 sale plus one intervening kill). Re-docking stayed at 36 gold with sale 0. Right-click in safe waters left velocity zero and destination empty. Misses also ended casts immediately. The native UI tool's delayed frames made precise reeling difficult; capture telemetry and a timed native keypress verified the actual successful input without modifying gameplay state.

Evidence: simple-run-victory, single-reel-catch, automatic-catch-sale, automatic-sale-revisit, no-right-click-steering PNG/TXT pairs. Saved silver/progression retained; game left at title. Broader balance across other builds and extended endless play was not re-evaluated.

## Fishing result simplification — 2026-09-08

Removed Catch mode and its result panel/confirmation input. Success and failure resume sailing immediately, with a 2.5-second boat-following label. Live native play verified failed casts and a successful Silver sprat (14 gold value): mode Sailing, cargo 1, gold still 20. A later capture shows the combat clock advancing from 6.04 to 14.48 seconds, steering destination/velocity active and cargo retained. The label faded away. Debug build passed with no warnings/errors; no injected state or automated tests. Timeout uses the same failure resolution path but was not separately timed in this check.

## Unlimited catches — 2026-09-08

Removed the 12-catch interaction gate and full-hold warning. The result-popup removal had already removed the visible cargo counter; source inspection confirms only the diagnostic capture count remains. Catch accumulation and automatic dock sale/clear are unchanged. Debug build passed without warnings/errors and the rebuilt native game opened successfully. This focused check did not include a 13-catch live voyage; no automated tests or state injection were used.

## Clear boat abilities — 2026-09-08

Removed movement-dependent mitigation and pulse charging, Cutter after-release bonus, and incidental pulse damage/soak. Trawler now pulses every six simulation seconds; Cutter cooldown progress accelerates by 65% only during active boost. Debug build and native launch passed; boat selection copy inspected. A stationary Trawler live run advanced beyond two pulse intervals with charge wrapping. Live checks did not separately measure Cutter shot cadence or projectile clearing; those paths were inspected in source. Damage is now unmitigated for both boats, so a full-run balance pass remains useful. No automated tests or injected state.

## Single-improvement upgrades — 2026-09-08

Audited all weapon-rank dependencies and replaced bundled damage/cadence/area scaling with one property per weapon. Matching card copy distinguishes acquisition from upgrading. Debug build passed without warnings/errors, diff whitespace checks passed, and native startup/sailing were checked. No automated tests or injected state. Every rank was reviewed in source; a full live run across all weapons/ranks was not performed. Balance needs a follow-up play pass because rank damage/cadence bonuses were removed.

## Visual and sailing simplification — 2026-09-08

Implemented distinct procedural pickup silhouettes, quieter combat particles/trails, hostile projectiles above friendly effects, larger and less frequent ordinary islands with three landmark styles and grouped rocks, rank-aware weapon visuals and shared whirlpool radius. Soaked state, slowing, damage multipliers and current copy are removed. Levels bank choices; docking resolves them before the shop. Harbor spacing is now two chunks, supporting the new refit cadence. Pending levels have a gold LVL hint.

Debug/Release builds pass. Native play reached level 3 and 35 kills over roughly 141 seconds of combat, traversing home and eastern harbor waters. Captures prove a level did not interrupt sailing, a free choice appeared only on docking, and selecting Harpoon returned to Harbor with no gold cost or combat-clock advancement. A subsequent level again banked during combat. Treasure collection, repair, harpoon pulls, enemy shots and larger landmarks were observed. One initial palm polygon triangulation error was fixed; the subsequent play session ran without that error. Captured frame mean was 9.91 ms, p95 14.73 ms at 126 seconds with 25 loaded chunks.

Limits: this was not a boss-victory balance run. Multiple simultaneous pending choices and the fully-maxed gold fallback were reviewed in source but not reached in native play. High-rank barrel/coil/radius visuals were checked in code; the live run used rank-one weapons. Final LVL hint and barrel-spacing adjustments followed the recorded gameplay captures. These are verification limits, not additional implemented mechanics. No automated tests, injected state or external art were used.

## Gunboat, Mage and Aura — 2026-09-08

Replaced Broadside with homing Arcane Orbs throughout simulation, offers, icons, boat art and current copy. Gunboat starts Cannon, Aura starts Whirlpool, and new Mage starts Arcane Orbs. Violet crystal/roof and orbiting lights distinguish Mage. Debug build passes without warnings/errors; native selector verified all three options. A moving Mage run recorded seven casts and three kills by 17.7 seconds with only its starter equipped. No sideways target gating remains. The new homing steering was reviewed in source; full-run balance and high-rank multi-orb behavior were not exhaustively playtested. No automated tests or state injection.

## Approved concept visual pass — 2026-09-08

Implemented the sea, beach/shallows, vegetation/landmark, boat, creature, wake/trail and pickup requirements in ART_DIRECTION.md. No core gameplay files changed. Compared native screenshots directly with the approved generated reference, then strengthened foam and corrected Mage crystal orientation. The result retains the existing camera/HUD and is more graphic than the illustration, with deliberately less foam/microtexture.

Debug and Release builds pass with zero warnings/errors. Native runs exercised moving Mage, homing orbs, crabs/puffers, shoreline streaming and collection; the title also rendered the revised serpent, and all creature animation strips are baked on startup. At the saved motion capture: frame mean 13.37 ms, p95 16.67 ms; a later busy capture measured mean 14.07 ms, p95 16.67 ms, with 25 loaded chunks. Logs after fixes contained no ERROR/WARNING lines. An initial nested-shell triangulation issue was fixed by keeping the rings properly inset; transparent cached shelves were corrected with premultiplied alpha; a nested-transform fish-shadow regression was fixed before final checks.

Limits: these are native visual/performance checks, not a fresh full boss-victory balance run. The final sparse sand grains and rounded Ray body were rebuilt after the saved gameplay captures. No automated tests, injected state or generated bitmap game assets were used.

## Concept depth revision — 2026-09-08

Replaced concentric shoal polygons with irregular vertex-colored shelves, softened beach and green-bank transitions, and removed quantized ocean depth. Revised cabin extrusion to remain upright as the boat rotates; added fuller faceted palm leaves and a pitched-roof cottage with side-wall depth. Wake edges now have irregular curls. No core gameplay changes.

Native comparisons exposed an overly luminous shoal gradient; the user rejected the resulting look and the old harbor house. Darkened the shelf and rebuilt the house, but this remains an intermediate result, not concept acceptance. Palm leaf quad triangulation errors were corrected with explicit triangles; latest runtime log has no ERROR/WARNING lines. Debug build passes. Latest native evidence: `concept-depth-revision.png/.txt`, early Mage sailing at six seconds, four enemies, 25 chunks, mean 17.25 ms / p95 16.67 ms / p99 41.53 ms including startup. Earlier revisions were checked while steering and firing; this final capture does not establish sustained combat performance or a final visual match. No automated tests or state injection.

## Sculpted landmark iteration — 2026-09-08

Replaced the seven-face tapered pillar with a seeded four-tier 3D vertex mesh projected into the existing 2D scenery cache. Face normals determine lighting; the shape has irregular ledges, a small summit, soft beach shadow, buttress rocks and foreground shrubs. Collision, generation and camera are unchanged.

Debug/Release builds pass and native logs have no ERROR/WARNING lines. Normal sailing exercised streamed terrain, crabs, puffers, serpents and homing orbs; runs ended in defeat around 36–45 seconds. A first light direction left visible rock faces too dark and was corrected. The native UI showed the corrected mesh, but saved gameplay captures did not provide an unobstructed close comparison: landmarks were partly offscreen or covered by the defeat panel. This remains a verification gap; do not count the landmark as visually accepted. Earlier 36-second run measured frame mean 11.88 ms, p95 16.67 ms, p99 17.28 ms; subsequent early run after the light change measured 10.49 / 14.83 / 16.95 ms. These timings do not establish long-session performance. No automated tests or injected state.

## Water structure iteration — 2026-09-08

Replaced smooth vertex-gradient shoals with a dedicated seeded shoreline shader baked under static land. It follows the beach contour, adds local depth variation and fades into the surrounding water. Reworked ocean noise into warped depth fields and finer directional ripples; added explicit rock shoulder ledges after an unobstructed native view showed the previous mesh still looked conical. Native checks caught overly prominent ripples and a dark shelf edge; both were softened. Debug/Release builds passed, and subsequent native startup rendered the final shader without ERROR/WARNING lines. A 35-second Aura run exercised the preceding edge version during combat; final softened edge was checked at startup. This remains intermediate visual work, not concept acceptance.

## Immediate level-up choices — 2026-09-08

Level thresholds now open Upgrade mode during sailing. Each free selection resolves one earned level, then returns to Sailing; harbor entry only sells catches and opens its paid stock. Removed the harbor-refit prompt, banked-level tooltip and outdated handbook/README instructions.

Verified through normal Gunboat combat: level 2 opened at 22.983221 combat seconds, at position (0,0), with 12 kills and no docking. Two captures 22 wall-clock seconds apart retained exactly the same combat clock and weapon cooldown, proving combat remained frozen. Selecting Lightning added rank one, consumed the pending choice and resumed Sailing at (0,0); the later capture shows a thirteenth kill and 33 gold, up from 32. The native UI immediately after choosing showed 32 gold, confirming no purchase charge. Debug/Release builds pass; no runtime ERROR/WARNING lines. Multiple simultaneous levels and maxed-out gold fallback were checked in source but not reached live. No automated tests or injected state. Evidence: `immediate-level-up` and `concept-water-and-refit` PNG/text pairs.

The resumed capture also records the final shore shader, quieter water ripples and ledged landmark unobstructed. Frame mean 16.63 ms, p95 16.67 ms, p99 18.06 ms at 26 seconds. The visual goal remains active: shores still look stylized and smooth; architecture, foliage and creature richness remain below the reference.
