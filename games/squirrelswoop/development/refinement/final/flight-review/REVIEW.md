# Corrected final-build flight review

Reviewed on 6 September 2026 using a real rendered Godot process, discrete manual flight commands, and actual InputEventKey down/up events through the normal keyboard path. No automated tests. Source stayed frozen: `source-sha256.txt` aggregate SHA256 `a1b09c55a6f3fc57686798f26c3bde0d05d9ce24273038d9281958ae8711ed5d`; every source file was rechecked unchanged after play (`source-verification.json`). Raw actions and snapshots are in `manual-play.jsonl`.

## Launch and reproducibility

The initial candidate exposed a reproducible 2.03-second neutral-launch branch collision. That superseded evidence is preserved in `pre-launch-buffer/`. Root extended the clear start to 100 m. On the corrected build, neutral launch survived 86 m / 4 seconds, continued past 323 m / 15 seconds, and naturally ended at 941.291321 m. The beginner regression is resolved.

Two corrected-build neutral runs using Enter and R key events reproduced exactly: position [-28.149076, -435.740753, -941.291321], speed 21.5 m/s, clearance 5.009542 m, score 1854.024654, and 3 close passes. Neither was staged. Different frame scheduling did not change this outcome. N also launched a new seed, 148583, from results.

## Continuous flight

- **Meadow:** seed 752041 reached 3210.114746 m over 150.3 seconds aloft, without staging, teleportation, collision suppression, or resets during the run. Pauses allowed observation and screenshots. A launch bank moved to x −60.91; visible openings prompted rightward correction to x −43.61 at 1787 m and leftward correction to x −66.94 at 2181 m. The resulting broad meadow line was relaxing and required occasional steering. See `continuous-3km.png`, `meadow-approach.png`, and `meadow-line-change.png`.
- **Pitch and momentum:** from 3055 m, five seconds of full pull increased clearance from 4.33 to 14.95 m while reducing speed from 21.49 to 16.59 m/s. A short actual Space-key dive reached 22.25 m/s at release, with 12.82 m clearance. After roughly 0.8 seconds spreading, 22.03 m/s remained at 10.61 m clearance. This is demonstrated altitude/speed exchange, not a claim that subjective fun was proved.
- **High-speed collision:** holding the next dive caused a ground impact at 3210.114746 m, speed 30.076 m/s (108.27 km/h), clearance 0.374 m. The results screen identified the ground and advised earlier release; the true continuous-run record became 3210 m / 3510 points. See `high-speed-results.png`.
- **Stream and free crossing:** a fresh seed 482193 launch bank entered the stream at 40.73 m (x −6.28, route 1), continued to 236.84 m (x −0.56, clearance 7.44 m), then a 2.7-second left bank freely crossed into meadow at 296.81 m. The run remained alive at 310.36 m. See `continuous-stream-entry.png`, `continuous-stream-bend.png`, and `continuous-stream-to-meadow.png`.
- **Continuous woods entry:** another fresh seed 482193 run crossed meadow and stream into the first forest passage at 118.74 m / x 46.33. It remained alive at 252.61 m. A visible opening to the right plus 1.6 seconds of pull moved toward the second passage, but the resulting height met an upper tree obstacle at 297.32 m / x 72.86 / clearance 10.36 m. The obstacle is visible in `deep-woods-second-passage.png`; the results identify a limb. This was a failed line choice, not evidence that a broad pull guarantees safety. See also `woods-entry.png` and `woods-opening.png`.
- **Second-seed woods:** seed 915772 continuously entered to x 64.95 / 164.75 m. After foregrounding the window, a further rightward line at substantial altitude met a branch at x 70.99 / 180.26 m. These attempts verify access and demanding upper-limb risk, but do not establish a long successful second-passage descent from launch.

## Additional explicitly staged deep-woods study

To inspect a representative second passage separately from the failed continuous entries, seed 915772 was positioned at distance 420 m, x 80, clearance 6.5 m. The scene then generated fully before the main observation. Actual forward flight at x 80 continued from 433.56 to 611.58 m, passing large trunks and approaching boulder shoulders; clearance ranged from 9.06 to 2.38 m, with ground assistance recovery intensity 0.288 near 609 m and speed 21.14 m/s. `staged-deep-woods-traverse.png` and `staged-deep-woods-rock-shoulders.png` visibly say STUDY. This is not a continuous-from-launch claim. The initial `staged-deep-woods-approach.png` predates full ahead-generation and should not be used as a representative beauty capture.

## Settings, menus, and persistence

Actual Tab/Enter navigation opened settings from pause. The slider Left key changed volume from 0.70 to 0.65; Tab/Space toggled assistance off, reduced motion on, and invert pitch on. Done returned to pause. `settings-changed.png` and `settings-before-restart.cfg` record these changes.

The review process was explicitly quit and restarted with the same project and port. A fresh process loaded the 3210.1147 m / 3510.614746 record and the changed settings; the before/after config copies contain the same persisted values. `persisted-summit.png` records the loaded summit. Original review preferences were restored to volume 0.70, assistance on, reduced motion off, invert pitch off. Enter launched and Escape paused the new process. Handoff: PID 58860, port 45891, paused at 4.362 m, seed 482193, staged false. The restart console showed the Godot 4.7.2 / Apple M3 Max startup and capture messages, with no script errors through handoff. The development profile is separate from the normal player save.

## Performance and limits

Configured window 1280×800, logical viewport 1440×900, OpenGL compatibility, MSAA off, Apple M3 Max. Three other Godot games were observed at corrected-run start; there had been four earlier. Other tasks restarted their processes during this session. See `conditions.txt`.

Selected foreground, no-capture windows during the 3 km run:

| Checkpoint | Frame p50 / p95 / max | Physics snapshot | Last generation slice |
| --- | --- | --- | --- |
| 1030.64 m | 41.844 / 58.354 / 81.488 ms | 3.956 ms | 4.102 ms |
| 1783.74 m | 45.814 / 66.448 / 88.339 ms | 0.575 ms | 9.479 ms |
| 2176.47 m | 35.579 / 46.661 / 58.380 ms | 0.346 ms | 4.732 ms |
| 3051.29 m | 35.343 / 46.483 / 57.282 ms | 0.217 ms | 4.305 ms |

These are shared-machine observations, not a solo 60-fps claim. Woods were slower: the foreground first-passage window to 249.78 m had frame p50 55.71 ms / p95 74.916 ms; physics snapshot 0.215 ms and last generation slice 4.760 ms. Snapshot physics and slice values are not maxima over the window. Startup seed regeneration remains synchronous and slower than rolling slices.

RSS samples during the 3 km descent were 375920, 377904, 380768, and 379728 KiB (roughly 367–372 MiB). Loaded sections settled at 63 and cached vertices around 17250 while total generated sections increased to 410 at 3051 m. This supports bounded memory for this run, not an indefinite leak proof.

After the 3 km window, another application occluded the review window. Rendering counters froze and some screenshot requests were deferred, while physics continued and telemetry reported approximately 145 fps. Those intervals, especially the first seed-915772 entry, are excluded from rendered performance claims. Only the target process was foregrounded at 07:34 UTC; foreground woods observations then resumed. Screenshot calls themselves caused approximately 0.5–0.7-second stalls, excluded from the no-capture metrics above.

Remaining limits: no physical-controller play or independent audio listening was performed, and fun is not established by telemetry. The unchanged assistance model's matched on/off comparison and long-pull boundedness were reviewed in cycle 1, rather than repeated as final-build paired studies. The continuous deep-woods attempts were short and fatal; the longer second-passage observation has an explicitly staged start. Canopy detail remains visually busy at upper-limb height, and the stream still reads as a narrow ribbon in some views. The woods now visibly demand line and altitude decisions, but broader human play would be useful for judging readability and difficulty at speed.
