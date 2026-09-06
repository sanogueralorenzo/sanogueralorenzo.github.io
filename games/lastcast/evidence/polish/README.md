# Last Cast — before/after evidence

These captures and events document the September 5–6 polish pass. Read [POLISH_VERIFICATION.md](../../POLISH_VERIFICATION.md) for exact scope, assisted-input disclosures, performance and limitations. The reference image remains outside the repository and game.

## Before and after

| View | Before | Revised |
| --- | --- | --- |
| Walking | [Original harbor](before-walking.png) | [Revised walking](after-walking.png), [walking and purchase recording](after-harbor-walking-and-purchase.mp4) |
| Boating | [Original boat](before-boating.png) | [Final moving skiff](final-corrected-wake.png), [corrected wake recording](final-corrected-wake.mp4) |
| Fishing | [Original fishing](before-fishing.png) | [Revised fight](after-fishing.png), [normal fight and landing](final-normal-fight-and-landing.mp4) |

[Baseline recording](before-gameplay.mp4) is a 58-second excerpt using the previously earned original-build replay; it includes a missed strike and does not prove a catch. Baseline walking used a zero-shell save. The boat/fishing baseline used the previously earned replay, not a seeded new save.

The revised walking clip uses normal game pace and includes a permanent rod purchase. The final fight clip contains an uninterrupted normal-pace common fight after assisted hook setup; the gear is an earned upgraded rod plus Silk leader. The final wake clip shows actual coastal translation after the foam winding correction. MovieWriter uses fixed engine stepping and is not a performance benchmark.

[Stair ascent/descent](assisted-stair-traversal.mp4) uses Focus for precise positioning. It demonstrates connected traversal, not normal-speed movement feel.

## Progression, skill and failure

- [Fresh boat purchase](fresh-boat-purchase.png): three banked summer bream earned the 65-shell skiff.
- [One signature read](signature-dash-read.png) and [two reads](signature-two-dashes.png): explicit counter/held/reel feedback.
- [Boat signature landed](boat-signature-landed.png): Sunscale Mullet remained unbanked until returned.
- [Winter koi at the feint and 92% skill gate](winter-koi-feint-skill-gate.png): one response still required, even with a purchased rod.
- [Winter sailfish responses](winter-sailfish-two-reads.png) and [corrected full-fish hold](final-sailfish-held-clear.png).
- [Earlier koi hold defect](winter-koi-landed.png) is retained only to show the diagnosed pier intersection fixed by the final pose.
- [Permanent rod purchase](permanent-rod-purchase.png), [manual rescue loss](manual-rescue-loss.png), [automatic sunset loss](automatic-sunset-loss.png), [fresh replay supplies](fresh-replay-supplies.png), [autumn coast](autumn-coast.png).

The signature presentation/reads used Focus and manual pauses; their final retrieves included normal-pace segments. These demonstrate rule execution and visual feedback, not unassisted mastery or a measured claim of fun. Independent agents reviewed concrete source behavior and fresh captures; substantive findings were corrected and checked again.

## Earned saves and local event record

- [First boat milestone](fresh-boat-earned.json): 7 shells, boat owned.
- [Jade unlock](fresh-jade-unlocked.json): 77 shells after returning the Sunscale signature.
- [Stormglass unlock and equipment](fresh-stormglass-unlocked-equipped.json): 40 shells, rod 2, creel 2, both coasts unlocked.
- [Final earned replay](final-earned-replay-save.json): 344 shells, all permanent gear and winter mastery, day 8 safely in harbor.
- [Fresh voyage events](fresh-voyage-events.jsonl): game-local events from the fresh zero-shell run onward, including failed attempts, purchases, catches, banking, rescue and screenshots. Some screenshot entries refer to additional user-data captures not included here.

The original local pre-polish save was restored after verification. To inspect the earned replay, first back up your own `user://last_cast.json`, then copy the chosen evidence save there while the game is closed. The game never loads evidence saves automatically.
