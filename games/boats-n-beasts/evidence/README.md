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
