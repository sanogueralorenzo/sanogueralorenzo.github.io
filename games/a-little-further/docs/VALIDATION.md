# Native validation and local evidence

Validated on **7 September 2026** with native **Godot .NET 4.7.2**, C#/.NET **10**, **Forward+**, and **Metal 4**. The redesigned game uses the separate worktree and native development application.

## Hardware and final settings

MacBook Pro **Mac15,10**, Apple **M3 Max**, 14 CPU cores (10 performance + 4 efficiency), 30 GPU cores, 36 GB unified memory. macOS **26.5.2 (25F84)**. Final window/captures: **1920×1200**, 1440×900 logical UI, 2× MSAA, directional shadows, SSAO, glow, depth-based shore foam, and a **60 fps target**. Rendering is full resolution. This is a development machine, not a clean laboratory system.

## Scale and voyages

The [16-island survey](island-survey.json) covers four seeds and four signed cells per seed. Land area (height > 0, two-metre samples) ranges **26,452–36,116 m²**, averaging **30,609.75 m²**. CozySora’s Seabreeze horizontal boundary mask measures **30,115 m²**. The masks are comparable benchmarks, not identical collision-area measurements. See [redesign details](REDESIGN.md).

First sighting means entry into the actual native visibility/fog range, not arrival or merely a generated neighbour. Measured purposeful full-sail crossings:

| Seed / route | First sight after departure | Distance to destination centre | Speed |
|---|---:|---:|---:|
| 73919: (0,0) → (1,0), normal native run | 105.29 s | 724.64 m | 26.95 m/s |
| 1701: (0,0) → (1,0), native movie | 114.29 s | 712.95 m | 26.95 m/s |
| 1701: (1,0) → (1,1), native movie | 120.06 s | 722.63 m | 26.95 m/s |
| 1701: (1,1) → (1,2), native movie | 120.39 s | 722.90 m | 26.95 m/s |

Recorded crossings use simulation seconds at the movie’s fixed step. The separate normal native seed verifies comparable real-time pacing. Returns to known shores and the initial visible island are not presented as new-discovery crossings. Travelling without full sail takes longer.

## Played runs and inspection

All images/video remain under `~/GameSourceVault/a-little-further/evidence`, outside Git because they depict proprietary recovered material.

| Directory | Coverage and result |
|---|---|
| `redesign-full-73919/` | Complete **1920×1200, 30 fps, 315.97-second** recording, including native chart-pause inspection, two islands, recruitment, natural death at 273.23 s of active run time, and fresh seed 73920. Main deliverable: `a-little-further-full-run.mp4`. |
| `redesign-final-73919/` | Final normal native run: two islands, one completed shrine, recruitment/provisioning, 40 kills, 208 doubloons; natural death at **273.23 s**, then seed **73920** with 100 health, one rank-one Gunner, and zero progress. |
| `redesign-release-1701/` | Final 1920×1200 movie: four islands, three completed shrines, four crew berths, developed Gunner/Stormcaller/Duelist plus Harpooner, 187 kills, three rebases. The pilot reached its 720-second validation limit **alive** (711.08 s of active run time; 81.2 health). `four-island-voyage.mp4` is a long voyage demonstration, **not** a death/restart recording. |
| `redesign-manual-land/` | Ordinary manual sailing/disembarkation, click movement, jumping, auto-attacks, a cairn side trail and its 24-doubloon payout/opened chest. The session ended by closing the application after 107.33 s; it is not claimed as a death run. |
| `redesign-hd-73919/` | Assisted initial approach, manual chart/camera/interaction checks, then resumed pilot; natural death at 200 s and fresh restart. Camera tap changed yaw from 3.1477103 to 3.0077102. This exposed the chart-time issue fixed afterwards. |
| `redesign-art-inspected/` | Explicit render inspection of all four discovery types and all seven captain/role appearances. Camera-only art review; no played-run credit. |

The native pilot issues ordinary movement, jump/glide, dodge, interaction, provisioning and choice commands. It does not teleport, grant health, fabricate kills, or force death. Automated play is identified in the HUD. Manual sections and camera-only art inspection are reported separately.

The [chart audit](chart-pause-audit.json) records two native keyboard-triggered snapshots separated by more than 500 movie frames: run time remained **38.883335 s**, health **82.4**, gold **81**, and kills **6**. Escape closed the chart and resumed the encounter. The MP4 contains 1920×1200 H.264 video and 48 kHz stereo AAC audio. A complete decode found no audio errors; measured peak is −11.6 dBFS (no clipping). A frame extracted at 8.6 s in the long recording verifies the recovered glider mesh and animated wing treatment during an actual hop/glide.

## Frame pacing and extended travel

**Performance sign-off remains open.** Both ten-minute native passes retained nine island roots, completed five origin shifts, and performed 29 builds / 15 evictions. The [complete timing data](travel-performance.json) preserves the outliers and conditions.

| Pass | Median | p95 | p99 | Maximum | Frames > 50 ms |
|---|---:|---:|---:|---:|---:|
| Before capture fix; no other game/encoder observed | 16.666 ms | 17.397 ms | 18.501 ms | 1,017.835 ms | 8 / 35,780 |
| After capture fix; concurrent CozySora preview | 16.677 ms | 28.105 ms | 105.714 ms | 1,033.767 ms | 723 / 30,741 |

A focused 60-second trace identified a 173.249 ms frame at the synchronous screenshot, whose PNG operation took 171.156 ms. PNG compression now runs off-thread. The subsequent start/end captures used 8.078 / 14.218 ms main-thread readback, with 163.976 / 220.001 ms compression on the worker; both files completed before shutdown. This fixes the capture-induced stall, **not** the separate one-second outlier.

The repeat trace recorded a 1,010.891 ms interval at run second 73.45, approximately coincident with the other Godot process starting at 17:27:17 local time. Later long frames occurred without new island builds. That correlation suggests external contention but does not prove its complete cause. The second preview remained active at over 100% CPU after this run; `pmset -g therm` reported no thermal/performance warning. Do not present this concurrent run as a clean benchmark or claim that all stalls are resolved. An isolated GPU retest remains necessary. Earlier movie metrics are not substituted: writing movies, GUI inspection, and other rendering/encoding work alter wall-clock intervals.

The diagnostic uses a monotonic microsecond clock between native process callbacks, omits the first 120 samples, and retains at most 60,000 intervals. It records percentiles, long-frame counts, maximum interval, builds, evictions, origin shifts and resident roots. The bounded slow-frame trace includes startup frames, while percentile/count summaries omit the first 120 samples. Screenshots and metric files are diagnostic artifacts and are never loaded as game state.

The movies precede the final capture-only change: PNG compression now runs on a background task, and shutdown waits for it. Gameplay, art, camera, and UI are unchanged by that fix.

## Focused checks and fixes

`./games/a-little-further/launch.sh --check` passes **413,985 checks**. Coverage includes four-seed finite/deterministic terrain; coast-derived landing and inland/boat exits across 520 island/seed combinations; actual treasure-route traversal on non-starter islands; indexed mesh bounds, normalized normals and agreement with traversal heights; combat/rewards; marked Gunner damage, chill/harpoon shatter and chained hits; four-berth development/replacement; death/fresh state; and a 1,300-second core voyage with **12 origin rebases**.

Native iteration fixed the submerged third landing, diagonal docking stall, large block-like rock selection/scale, subpixel foliage loss, foreground occlusion, scenery obscuring caches, disconnected telescope legs, cache/coin intersection, invisible old HUD input strip, Retina text scale, and chart-time advancement. The final build has no C# warnings/errors; the private manifest verifies **29 files**. Bash syntax and Git whitespace checks pass. The original checkout’s unrelated CozySora work was left untouched.

## Limits and historical evidence

The earlier `release-*`, `redesign-first`, `redesign-second`, and `redesign-third` directories preserve before/iteration evidence. In particular, the second redesign stalled on a diagonal landing approach, and the third exposed a submerged landing. `failed-movie-path` records a failed output-directory attempt; the launcher now creates movie parents before starting Godot. Partial encodes are not deliverables.

One Mac/GPU configuration is validated. No Windows/Linux native test, controller support, complete source-game skeletal retargeting, or independent human playtest panel is claimed. There are three foliage palettes, four discovery types, two enemy silhouettes, six crew roles and four berths. Complete Megabonk AI/item/hit-feedback source remains unrecovered; exact concrete translations and authored adaptations are distinguished in [provenance](PROVENANCE.md). The Last Cast and local SNØ port remain excluded.

Run state exists only in memory. Restart constructs a fresh world/core and clears rewards, encounters, visited islands and crew development. State-audit JSON contains validation summaries, not a save/checkpoint format or recovery mechanism.
