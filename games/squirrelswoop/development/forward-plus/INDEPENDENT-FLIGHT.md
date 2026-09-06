# Independent Forward+ flight and performance review

Reviewed 6 September 2026 by an independent flight/performance agent. Godot 4.7.2, macOS 26.5.2, Apple M3 Max, 36 GB RAM. Source review checked the original verification, refinement findings, visual reference, and review protocol. Flight model, generation, collisions, controls, HUD, scoring/progression, and save/load routines have no implementation changes in this migration. Source fingerprints in `flight/source-sha256.json` were rechecked unchanged after play. The longer lifecycle evidence below predates the opaque foliage-core correction; the final follow-up at the end closes that rendering defect and verifies the corrected source/export. Gameplay, saves and long-descent observations apply to unchanged game logic. No automated tests were created.

## Source and standalone desktop execution

The final macOS release exported successfully without warnings/errors, was copied outside the repository to `/tmp/swoop-independent/Squirrel Swoop.app`, and passed `codesign --verify --deep --strict`. The 163 MiB bundle ran from `/tmp` without `--path` or repository access requirements. Both source and release logged and reported actual **forward_plus / metal / Apple M3 Max**. The source override `--rendering-method gl_compatibility` exited **1** with only the intended renderer requirement error; no subsequent nil-object or gameplay error appeared.

All selected engine viewport PNGs are **1280×800**, verified from PNG headers in `flight/images.json`. The project retains logical 1440×900 canvas layout with 1280×800 default window. Its stretched texture proxy reports 1138×712; that is not the image resolution. One rendered game was active throughout the review under `/tmp/godot-exclusive-runtime.lock`; other tasks' pre-existing games were already suspended. The exported window was raised through CUA. Startup, seed loading and all capture spans are excluded from the selected timing windows.

## Reproducibility, flight, and lifecycle

- **Exact exported neutral run:** Enter launched seed 752041 from the summit. It reproduced the established **941.291320800781 m** collision, position `[-28.149076461792, -435.740753173828, -941.291320800781]`, speed 21.5 m/s, score 1854.02465413411, and three close passes. This independently matches the original Compatibility and final source outcomes. Actual R key events retried the same mountain.
- **Continuous long descent:** after a 2.6-second launch bank, the final export held approximately x −67.56. A right bank at 1,823 m moved to x −43.98; a later left bank at 2,426 m restored x −67.56. It reached **3,186.009 m alive**, 6.704 m clearance, 63 active sections, 441 generated sections, no pending backlog. The capture shows 3,187 m; Escape paused at 3,190.310 m. This run started at the summit and used no staging, teleportation, collision suppression, or reset during the descent.
- **Altitude and energy:** actual S key held for about three seconds changed speed 21.50→16.92 m/s and clearance 4.39→13.22 m. A 0.7-second Space dive reached 23.12 m/s at 10.37 m clearance. One second after release, speed remained 22.58 m/s and clearance 9.34 m. The run continued normally afterward.
- **Deliberate impact:** after resuming at 3,190 m, holding Space produced a ground collision at **3,216.593506 m**, 28.085 m/s (101.1 km/h), 0.360 m clearance. The result identified the ground and recorded **3,816.760 points**. No tunneling was observed.
- **Free crossings:** another export run, seed 482193, banked from meadow through stream into woods at 108.707 m / x 42.153. A later repeat captured woods flight at 113–123 m; a left bank returned to the stream at 196.331 m / x 3.289, alive. These views are continuous from launch. No staged scene was used in this independent review.
- **Expected failed lines:** an earlier meadow attempt held x −64.55 and hit a visible tree limb at 1,989.555 m; the successful run's correction avoided that region. A separate woods line held x 47.91 and hit an upper obstacle at 414.060 m / 9.315 m clearance. These are failed steering choices, not proof that every obstacle is readable or every route is safe.
- **Pause:** actual Escape events exercised source and export pause/resume. Source position and distance stayed exactly frozen across subsequent snapshots. Export paused and resumed the same long descent.
- **Saves:** returned to summit, changed volume to .35, assistance off, reduced motion on, invert pitch on, then quit the release process. A newly launched standalone release loaded all four settings and the new **3,216.5935 m / 3,816.76017252606** records. Changes used the opt-in settings action; previous reviews cover physical menu navigation. Original `development.cfg` was backed up and restored afterward. Normal `swoop.cfg` was untouched.

## Comparable performance observations

Selected no-capture active-flight windows in the standalone release:

| Window | Frames | p50 / p95 / max frame interval |
| --- | ---: | --- |
| Neutral seed 752041, 546→941 m | 1,101 | **16.665 / 18.145 / 21.476 ms** |
| First meadow attempt, latest 1,800 frames before 1,423 m | 1,800 | 16.664 / 18.702 / 21.539 ms |
| Successful meadow run, latest 1,800 frames before 1,822 m | 1,800 | 16.659 / 18.833 / 21.763 ms |
| Successful meadow run, latest 1,800 frames before 3,186 m | 1,800 | **16.670 / 19.181 / 22.660 ms** |

The game reported 60 FPS at these checkpoints. This supports a mostly 60 FPS experience on this machine, **not a locked 60 FPS claim**: p95 exceeds the 16.67 ms budget. Root's isolated matched neutral Compatibility window is the appropriate renderer comparison; the earlier refinement's concurrent-game results are not comparable. Screenshot writes produced approximately 277–280 ms stalls and are explicitly excluded above. Woods capture spans cannot serve as clean performance windows.

OS process RSS was 402,160 KiB after neutral flight (**392.7 MiB**); subsequent samples through repeated runs and capture activity were 416.5, 432.3, 434.4, and **451.4 MiB**. The final sample was before the 3,187 m screenshot, after prior captures and retries in that process. These are total resident-memory observations, not a no-leak proof or an exact allocation delta attributable to Forward+. Active sections settled at 63 while total generation continued. Release-template static allocation monitors return zero and are treated as **unavailable**, not as zero memory consumption. Raw RSS, commands, snapshots, and runtime logs are in `flight/`.

## Movement and visual judgment

Inspected actual flight captures, banking and dive/recovery states, and the consecutive `woods-flight-a/b/c.png` sequence at 113.318 / 118.142 / 123.341 m. The sequence shows foliage moving past the camera, a bank settling, sunlight changing across the squirrel, and the forward opening remaining visible. It does not show temporal trails, broad terrain shadow ribbing, a blurred HUD, or smeared character edges. Stream return retains a readable channel, restrained reflected-sky highlight, and distinct bank stones. The meadow remains open and legible at ordinary and recovered dive speeds.

Close canopy detail remains busy. Thin needle-card edges produce fine dotted lines; dark solid triangular foliage cores are conspicuous when flying at upper-canopy height. Root agreed the dark cores are a substantive rendering defect and is removing the old opaque filler geometry while retaining the alpha needle sprays. These images document the pre-fix finding, not final visual acceptance. Fine shadow changes across fur and canopy are visible between frames. Sparse viewport captures, each of which stalls rendering briefly, cannot certify absence of high-frequency shimmer or every transient motion artifact; no full-rate human motion or physical-controller assessment is claimed. The reviewed openings, rocks, trunks, and squirrel remain distinguishable in the sampled motion sequence.

The requested summit A/B with background energy .65 versus 1 is saved in `trials/sky065.png` and `sky-default.png`. Lower energy changed pale sky to duller gray-blue without restoring saturation or materially improving geometry. Both root and independent reviewer preferred retaining 1; the paler sky relative to Compatibility remains an acknowledged atmosphere/palette tradeoff.

All game instances owned by this reviewer were quit and the exclusive lock released. Physical keyboard/controller feel, independent audio listening, other GPUs/operating systems, arbitrarily long runs, and continuous full-rate shimmer assessment remain outside this evidence.


## Final corrected foliage follow-up

**Accepted with the documented residual limits.** Root removed the four opaque filler triangles from each crown spray and deleted the shader's special core UV/alpha path. This changes visual geometry only; RNG calls, placement, collision, flight, controls and saves remain unchanged. The corrected source fingerprint (`flight/source-core-fixed-sha256.json`) was verified unchanged after the follow-up.

Repeated the full seed-752041 neutral descent from a warmed summit with no captures before results. It still ended at **941.291320800781 m**, identical position, speed, 1,854.024654 score, and three passes. Its final 1,800 active frames measured **p50 16.655 / p95 18.814 / max 23.202 ms**. Source RSS was **486,128 KiB (474.7 MiB)** at summit and **499,584 KiB (487.9 MiB)** after collision; an intermediate sample was 499,040 KiB. Static allocations were 97.84 MiB initially, 105.25 MiB finally, peak 107.75 MiB. This source process uses development debug monitors, unlike the release process above. It confirms near-60 cadence with occasional budget misses, not an improvement claim over the earlier neutral timing; OS residency varied appreciably between isolated sessions.

Recaptured all five documented matched after views, replacing `comparison/after-*.png`; previous versions are labeled `trials/pre-core-fix-after-*.png`. Each staged capture reports both pending 0 and building false. Camera transforms, seeds, world positions and heights are saved in `flight/corrected-captures.json`; PNG dimensions and hashes are refreshed in `captures.json`. Every image is 1280×800.

The corrected continuous source woods sequence (`flight/core-woods-flight-a/b/c.png`, 110.096 / 114.919 / 120.118 m) removes the large black wedges and markedly reduces the thin dotted card-edge streaks visible in the pre-fix sequence. The remaining alpha sprays still form full crowns. The central opening, solid branches/trunks, rocks and warm squirrel remain distinct; shifting sun/shadow patches read without trails or broad ground ribbing in the sampled frames. Fine needles and fur still have high-frequency detail, and sparse capture limitations still apply. A small phase-dependent cloud seam is visible near x615/y145 in the summit image; root confirmed the pre-existing sky longitude wrap. It does not obscure gameplay and is not hidden by selecting a different sky phase.

Re-exported macOS, Windows and Linux releases after the correction; all exited 0 with no warnings/errors. The corrected macOS bundle passed strict deep signature verification and was recopied to `/tmp`. It independently launched with Forward+ / Metal, Enter left the summit, a right bank reached woods at 109.065 m / x42.169, and Escape paused at 112.849 m. `flight/core-export-woods.png` shows the corrected canopy in the actual standalone release. Corrected source/export logs are clean. Windows/Linux exports were built, not run on their native operating systems.

The corrected source and exported app were both quit, the review profile restored, and the exclusive runtime lock released before the five-minute follow-up window ended. The substantive visual finding is closed; no remaining blocking runtime or source finding was identified in this review.
