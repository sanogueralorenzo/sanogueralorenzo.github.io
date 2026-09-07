# Native validation and evidence

Validated locally on **7 September 2026**. The game runs in native Godot .NET **4.7.2**, C#/.NET **10**, **Forward+**, using **Metal 4**. No browser runtime or compatibility renderer is involved.

## Hardware and settings

MacBook Pro **Mac15,10**, Apple **M3 Max**, 14 CPU cores (10 performance + 4 efficiency), 30 GPU cores, 36 GB unified memory. macOS **26.5.2 (25F84)**. Game window/captures are **1280 × 800**, UI logical viewport 1440 × 900, 2× MSAA, directional shadows, SSAO, glow, and depth-based shoreline foam enabled. Tests were windowed on the development machine, not a clean laboratory system.

## Gameplay checks

The local evidence root is `~/GameSourceVault/a-little-further/evidence`. Recordings and images are excluded from Git because they depict proprietary recovered assets.

| Evidence directory | What was exercised | Result |
|---|---|---|
| `manual/` | Native keyboard/click play: sailing, disembarking, treasure trail, jumping, shrine combat, death, Enter restart | Run ended naturally at about 184 seconds; restart visibly restored 100 health, one crew member, and zero rewards with a new seed. |
| `final-1701/` | Recorded native pilot: sailing, two distinct islands, two shrine fights, recruitment, provisioning | Two shrines completed, 43 enemies defeated. The retained 95-second MP4 covers the successful two-island section. This diagnostic preceded the final steering correction. |
| `release-1701/` | Complete 1280×800 native movie, from launch through death and fresh restart | Two islands, one shrine, 43 kills, 214 doubloons; natural death at 108.45 seconds, fresh seed **1702**. `a-little-further-full-run.mp4` includes the complete 117.5-second sequence with audio. |
| `release-73919/` | Full native pilot run after the shore-steering fix | Two islands, one completed shrine, 43 kills, 214 doubloons; natural death at 98.48 seconds during the second shrine. Fresh seed **73920** starts with no rewards or visited islands, one crew member, and full health. |

The final movie precedes only the behavior-equivalent private nearest-target loop substitution and diagnostic cleanup; that substitution is checked against the previous selection rule over 100 candidate sets.

The pilot issues ordinary movement, jump, dodge, interaction, and choice commands through the same core as player input. It does not teleport between islands, grant health, award fake kills, or force death. The HUD identifies automated play. Manual play and automated coverage are reported separately.

Reviewed captures include arrival, summit combat, the three-card recruitment choice, island departure, death, and the fresh run. Iteration corrected a wrongly oriented recovered enemy mesh, overbright terrain/water, shrine approach geometry, expensive uncropped wake shading, boat draw overhead, canopy occlusion, and a shore-assistance input cancellation. The final run confirms departure and arrival at a second island after the steering correction.

## Frame pacing and extended travel

The final travel test sails normally for 180 seconds with full sail, including cell eviction/building and origin rebases. It completed **6 origin shifts** and retained **25 loaded island roots**. Across 12,161 measured frames, median interval was **16.570 ms**, p95 **17.347 ms**, and p99 **20.656 ms**. This is near-60-fps pacing with occasional longer frames, not a perfectly locked 60 fps. The final sample had 220 draw calls and 512 rendered objects. See [raw benchmark metadata](travel-performance.json); gameplay captures remain in `travel-clock-1701/`. Frame intervals use a monotonic microsecond clock at consecutive native process callbacks; the first 120 samples are omitted. Movie Maker's fixed timestep is **not** used as a performance measurement. Earlier `release-73919` metrics used Godot's reported delta and are retained as diagnostic history, not the final wall-clock benchmark.

## Focused checks

`./games/a-little-further/launch.sh --check` passes **160,234 checks**. These cover deterministic finite terrain over four seeds (1, 1701, 73919, and 2147483647), bounded visible cells, reachable shrine traversal, auto-attacks and shrine rewards, four-berth development/replacement, recovered nearest-target eligibility/tie behavior, death/fresh state, steering away from shore, and a 1,300-second core voyage with **43 origin rebases**. They run without Godot references.

The native C# build passes with no warnings or errors. The complete MP4 has H.264 video and AAC audio; audio peaks at −12 dBFS with no clipping. A Movie Maker shutdown audit identified active WAV playbacks retained during immediate engine teardown. The game now stops audio and lets two mixer frames drain before normal close/quit; the normal native close audit reports no ObjectDB leaks. Verbose engine shutdown still lists two unclaimed shader-constant StringNames (`waves` and `timing`), retained here as a minor diagnostic limitation. Forced engine `--quit-after` bypasses the game’s orderly shutdown path. The private runtime manifest verifies 29 files. Launch/restore scripts pass Bash syntax checks and were exercised locally; ShellCheck is not installed. Public staging is audited separately to exclude the private package, generated build output, and gameplay media.

## Limits

This is one documented Mac/GPU configuration. No Windows/Linux native validation, controller support, full source-game skeletal retargeting, or independent human playtest panel is claimed. The game currently has three scenery biomes, two enemy silhouettes, six crew roles, and a four-hand cap. Complete Megabonk AI/targeting/hit-feedback source was not recoverable; the exact recovered routines/data and authored adaptations are listed in [provenance](PROVENANCE.md).

Run state exists only in memory. Captures and JSON metrics are diagnostic output, never checkpoints or recovery files.
