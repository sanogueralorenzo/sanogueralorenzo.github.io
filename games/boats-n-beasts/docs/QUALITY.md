# Quality and verification

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
