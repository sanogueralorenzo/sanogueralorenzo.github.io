# Last Cast — verification record

Verification used runtime play, visual comparison, independent agent review, source inspection, and Godot import/export checks. No automated tests were created. Times below are local to the September 5, 2026 play session.

## Environment and method

- Godot 4.7.2, macOS, Apple M3 Max, OpenGL Compatibility renderer.
- Built in the isolated `lastcast-worktree`, with the independently runnable project at `games/lastcast`.
- Native keyboard input through computer use; no save editing or debug unlocks were used to earn the recorded progression.
- Tool latency required toggle controls and Focus pace for timed hooks and signature fights. Common fights were also played at normal pace. Focus is a shipped accessibility setting; normal pace and held controls are the fresh-game defaults.
- The supplied reference was inspected beside gameplay captures. It is not included as an asset or backdrop.
- Both the editor-run project and the exported macOS release app launched. Focused GDScript checks and release export passed. The final live app reported no script errors during these flows.

## Demonstrated runtime flow

| Flow | Observed result |
| --- | --- |
| Introduction and fishing | Introduction, field guide, expedition choice, temporary upgrade, cast meter, lure presentation, visible strike, fight, landing, and return menus ran. Missed hooks spent one bait without ending the expedition. |
| Beginner shore economy | Three summer shore bream banked for 72 shells. Walking to Tackle & Tide and purchasing the 65-shell skiff left seven shells. |
| Normal common fight | First bream hooked at 16:53:07 and landed at 16:53:45, with roughly twenty seconds of its fight at normal pace after the opening Focus portion. |
| Line failure | Independent reviewer reproduced a full-tension break at 94% landing progress at 16:57:27. The earlier basket catch remained intact. |
| Boat and docking | Boarded, accelerated, stopped, reversed, steered, and returned. Right-side docking repeated at 17:20:49. Left-side docking repeated at 18:26:02 from (-2.5, 0.30, 4.0), placing the sailor on the main pier. |
| Boat value | An offshore Coral Snapper banked for 40 shells. The later winter signature was also caught from the skiff. |
| Permanent equipment | Bought rod level 1 and creel level 1; the latter increased carrying capacity from six to eight. Purchases survived successful returns, failure, and relaunch. |
| Upgrade combinations | Patient Hook + Golden Hour changed remaining daylight from 33 to 108 seconds and survived relaunch. Quick Spool + the permanent rod was used for the koi and winter sailfish. Silk Leader + the rod was used for autumn Albacore. |
| Save/resume | Multiple quit/relaunch cycles preserved banked shells, purchased equipment, unlocks, remaining supplies, temporary upgrades, and unbanked catches. Interrupted casts resumed as idle with their bait still spent. Boat owners resumed at the main pier. |

All regional gates were earned by banking actual signature catches:

| Signature | Location and season | Skill requirement | Banked reward and outcome |
| --- | --- | --- | --- |
| Sunscale Mullet | Shore, Sunwake summer | Spinner + Twitch; settled lure pulses; two clean dash responses | 70 shells at 18:05:38; Jade Lagoon unlocked |
| Moonpetal Koi | Shore, Jade summer | Float + Drift; announced feint and reversal; two clean dash responses | 130 shells at 18:22:22; Stormglass Reach unlocked |
| Stormglass Sailfish | Boat, Stormglass winter | Jig + Deep; release through paired runs; two clean dash responses | 304 shells at 18:46:37; winter mastery and coast completion displayed |

This also demonstrates continued shore usefulness after buying the skiff. All signature fights used Focus pace. The winter sailfish landed at 18:45:08; an earlier missed winter strike cost only its bait.

## Deadline failure and replay

An autumn offshore Albacore was hooked at 18:50:45 and landed at 18:51:05. The fight switched to normal pace immediately after hooking, used Silk Leader plus the purchased rod, and ended at 74% tension. Its unbanked value was 104 shells.

The boat remained offshore as daylight expired. Warm dusk lighting and the explicit return warning were observed. Automatic rescue at **18:54:43** removed that one unbanked catch. The **456-shell purse, skiff, rod level 1, creel level 1, both region unlocks, and winter mastery** remained intact.

A new summer expedition then began with **240 seconds, eight free bait, eight catch slots, and an empty basket**. Patient Hook was selected. Quit/relaunch restored that replay state. The resulting save is included as evidence, excluded from the game export, and was backed up outside the active save path before the final fresh-game launch.

## Independent review and corrections

Independent agents reviewed visual fidelity, movement, fishing satisfaction, beginner guidance, advanced challenge, and fairness. Their source findings are distinguished from actual play above.

- Continuous holding initially attracted signatures. Settled hold/release pulses are now required and explained.
- The sailfish's brief gap originally had conflicting reel advice. It now explicitly says to keep resting before the second run.
- Starter prices were aligned with the three-catch boat introduction. Pending earned upgrades now persist if their menu is closed.
- Permanent upgrades could initially bypass signature behavior. Every signature now requires a visible tally of clean dash responses before landing.
- Switching Focus could jump lure/dash phases and duplicate read credit. Phase clocks now advance continuously. Live koi play switched Focus → Normal → Focus without resetting the fish or its progress.
- The left docking approach was incorrectly rejected. The repaired trigger was repeated successfully in play.
- Camera-relative movement, boat arrow orbit, and camera collision during interpolation were corrected in source. The promenade and shop approach were replayed after the wall-occlusion fix.
- The fight panel and repeated bottom instructions obscured the action. Guidance was compacted and the fishing camera shifted to reserve HUD space. Independent review of live winter boat fighting confirmed the sailor, rod, line, and fish were visible; a final small offset adjustment also cleared the hull edge, repeated in autumn play.
- Smooth placeholder sea columns were replaced with irregular layered sea stacks, rubble, vegetation, and a curved rock arch. The revised landmarks were inspected in live autumn and winter views.
- Coarse foliage, geometric caustics, harsh materials, mirrored sign backs, and undersized modal backgrounds were corrected. Final comparison retained pastel architecture, dense leaves, turquoise water, soft sunlight, and a readable third-person view.

Manual F12 captures reported 60 FPS on the stated Mac, including approximately 737 draw calls during the winter boat fight and 1,245 on the detailed left-berth approach. Earlier batching reduced an independent preview from about 1,972 to 422 draw calls. Performance on other hardware is unverified.

## Evidence and limits

The [evidence folder](evidence/) contains selected runtime screenshots, the local voyage event log, and the verified replay save. An independent evidence audit reconciled the signature rewards, unlocks, rescue loss, and final purse against the log and save; no inconsistent core outcome was found. `evidence/.gdignore` and the export filter keep this material out of the playable build. `harbor-skiff.png` and the early shore captures precede the final HUD framing changes; the winter fight and autumn captures show later revisions.

The complete introduction-to-mastery, successful return, deadline failure, save, and replay route was demonstrated. Every possible seasonal species, full-basket boundary, upgrade combination, and input device was not exhaustively played. Boat arrow-key orbit and switching Focus exactly on a dash boundary were source-reviewed; normal-speed signature execution, controller support, and other operating systems were not verified.

These observations establish functioning controls and reachable progression, not that every player will find the game fun. No independent human playtest is claimed. The reference remains richer in painterly materials and architectural irregularity than this procedural interpretation; visual comparison guided revisions without implying pixel equivalence.
