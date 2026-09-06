# Independent flight and lifecycle review

Reviewer: independent flight/input/collision reviewer, 2026-09-05.

Method: actual Godot 4.7.2 graphical instances, isolated copied project and `user://` directory (`Squirrel Swoop Flight Review`), controlled through explicit manual launch/bank/pitch/tuck/pause/retry actions via the opt-in loopback review console. Screenshots are rendered gameplay. No automated tests were created or run. These controls demonstrate dynamics and state transitions; they do not establish keyboard/controller tactile feel or prove that the game is fun. Source was refreshed during development, so earlier screenshots show earlier visual revisions. Root owns the final visual comparison.

## Findings and fixes

- **Confirmed save overwrite defect:** saving a live-run record, resetting to summit, then saving settings could overwrite that record because the best values in memory remained stale. Root fixed `save_progress` to update those values before saving. Runtime persistence verification below reproduces this exact scenario successfully after the fix.
- **Confirmed unlimited pull-up clearance exploit:** negative trim was capped at `-0.22 * speed` while full positive pitch added `0.30 * speed`. Thus full pull at settled speed climbed relative to terrain indefinitely. Runtime seed 752041 reached 19.52 m clearance after only 5.3 s of sustained pull. Root changed the negative cap to `-0.34 * speed` and tapered lift with remaining speed. Follow-up result recorded below.
- **Controller input concern:** A was both launch/retry and held dive. Root removed A from flight dive, retaining RT. Code checked; no physical controller used.
- **Dive warning concern:** an original fixed 3 m warning gave too little reaction time. Root replaced it with projected time-to-ground. The revised warning was visibly present before a deliberate high-speed impact.
- **Momentum concern:** surplus speed initially decayed with a 0.86 s half-life. Root lowered surplus drag from 0.8 to 0.38 following review. This is a feel/tuning improvement, not a binary correctness finding.
- Fresh copied project originally failed to resolve global class names without an editor import. Root added explicit dependencies. A subsequent launch with no `.godot` cache succeeded directly.

## Demonstrated runtime behavior

| Check | Observation |
|---|---|
| Beginner meadow, seed 482193 | A gentle left bank for 2.8 s reached x=-58.93 / distance=60.99 m. Releasing all inputs for 20 s reached 489.95 m at 21.5 m/s and 6.67 m clearance. |
| Pulling up spends speed | From 489.95 m, 2 s full pull raised clearance 6.67→12.55 m while speed fell 21.5→17.50 m/s; vertical motion remained descending. This preceded the unlimited-pull fix. |
| Dive and recovery | A 0.7 s tuck raised speed 17.40→23.01 m/s while spending clearance 12.65→9.99 m. Releasing for 1.4 s restored stable glide at 7.28 m / 21.98 m/s. This preceded the surplus-drag adjustment. |
| Free route crossing, seed 482193 | Full right bank reached woods at x=41.75 / 110.17 m. Releasing stabilized x=46.65 / 121.92 m. Full left crossed woods→stream at x=4.99 / 189.00 m, then continuing left reached meadow at x=-56.67 / 274.63 m. Three close passes were scored. No teleport or route selector used. |
| Long beginner segment | Continuing that run without steering for 30 s reached 930.26 m / clearance=6.22 m. 63 active sections, 187 generated, pending=0. |
| High-speed terrain collision, seed 752041 | From elevated clearance, a deliberate 2 s tuck reached 30.64 m/s (110 km/h), 3.67 m clearance with the recovery warning visible. Continuing tuck hit terrain at distance=150.007 m / speed=32.249 m/s (116 km/h); the results screen correctly identified ground impact. No observed tunneling. |
| Exact retry reproducibility, seed 752041 | Two separate neutral retries struck the same visible tree at exactly 84.223831 m, position [-28.149076,-34.072079,-84.223831], speed 21.440159 m/s, score 92.223831. Reported FPS differed (23 vs 31). |
| Multiple seeds | 482193 and 752041 had different starting landscape/player coordinates and different neutral-run collision locations (149 m versus 84 m in the versions reviewed). Intentional left steering in 752041 survived beyond 439 m, establishing that the early neutral collision was avoidable. |
| Persistence across restart | At 930.26 m / 1242.99 points, returned to summit before collision, changed volume=.35, assistance=false, reduced motion=true, invert pitch=true, then quit. A fresh process loaded all four settings and records 930.25604 / 1242.9893758138. The isolated config was inspected directly. |
| Pause/resume and results | Repeated pauses preserved position and dynamics; resume continued the same run. Ground/tree impacts displayed explanatory results, and same-seed retries restored launch state. |

## Useful screenshots

These original captures were retained in the reviewer’s scratch directory. Selected copies are bundled in `evidence/`; the final root captures are listed in `VERIFICATION.md`.

- `stream-enter.png`, `woods-line.png`, `woods-to-stream.png`, `stream-to-meadow.png`: continuous route movement.
- `pull-up.png`, `recovered.png`: altitude management before final tuning.
- `high-speed-warning.png`, `high-speed-impact.png`: predictive warning and deliberate collision.
- `seed752041-neutral.png`, `seed752041-neutral-repeat.png`: repeated seed collision.
- `sustained-meadow.png`: 930 m run (paused overlay visible).

## Follow-up on final flight tuning

Full pull was held for 28.3 s on seed 752041 after the lift fix: clearance was 9.48 m at 57.68 m distance, then 8.20 m at 470.12 m after 25 more seconds. Speed settled at 16.50 m/s, vertical speed was -7.44 m/s. Clearance no longer grew without limit. This runtime used the revised lift and surplus-speed drag, but predates the later ellipsoid-rock/tapered-tree collider adjustment.

Continuing neutral flight for 40 s reached 1324.27 m with 5.14 m clearance, 21.50 m/s speed, one close pass, 63 active sections / 212 generated / pending=0, and reported 60 FPS. A second 40 s neutral segment reached 2184.54 m / 6.89 m clearance / 63 active sections / 310 generated / pending=0. A third 40 s segment reached **3044.70 m alive**, 5.65 m clearance, 21.50 m/s, one close pass, 63 active sections / **401 generated** / pending=0, reported 57 FPS. Captured `three-kilometres.png` while flying, then paused at 3047.56 m and quit to free the GPU. The run used no teleport and no steering after the initial 3.3 s meadow bank; the early 28.3 s pull-up segment is described above. These observations establish sustained streaming and stable active-section count for this route and seed; they do not prove every possible seed or route.


The isolated review instance has been shut down. No repository-owned source files were changed by this reviewer. Root has newer visual revisions and a later collider adjustment; root should use fresh final-build captures for visual acceptance.
