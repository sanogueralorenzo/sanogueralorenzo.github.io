# Native gameplay evidence

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
