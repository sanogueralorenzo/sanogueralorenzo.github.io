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
