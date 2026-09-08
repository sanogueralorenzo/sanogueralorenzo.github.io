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
