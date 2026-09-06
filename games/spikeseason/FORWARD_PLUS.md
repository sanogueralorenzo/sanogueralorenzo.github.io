# Forward+ migration

**Checkpoint committed at the user’s request.** Source and matched still reviews and six comparable performance runs are complete. Final movement/effect comparisons, final desktop exports, and independent exported-app controls/save restart checks remain unfinished. This is not a completed migration acceptance report.

## Baseline and ownership

The migration starts from the newer, uncommitted 3D iteration in `spikeseason-worktree`, copied into a new `spikeseason-forward-plus` worktree. The repository's `main` still contained the older 2D edition. The newer iteration already selected Forward+ but did not enforce it. Its source fingerprints are recorded in [baseline-manifest.json](evidence/forward-plus/baseline-manifest.json). The original worktree was preserved.

The migration keeps that iteration's perspective camera, procedural venue seeds, articulated athletes, fixed 120 Hz match director, inputs, scoring, progression and version-1 saves. The earlier 3D rebuild and balance changes are inherited work, not rendering-migration improvements. [Previous iteration findings](VERIFICATION.md) and [earlier 2D evidence](VERIFICATION_2D.md) remain historical records.

The original summer illustration and its approved six-player variant informed this work. The remaining difference in authored anatomy, scenery composition and painterly detail is not solved by selecting a renderer. No external visual asset is used by the game.

## Rendering contract

Godot **4.7.2** was installed on the verification machine. Development and desktop exports require Forward+ on a RenderingDevice backend: Metal, Vulkan or Direct3D 12. OpenGL fallback is disabled. The launcher rejects incompatible renderer arguments, and the game checks the actual renderer and device before initializing presentation or loading a save. A successful startup prints `SPIKE RENDERER method=forward_plus` with the actual driver, GPU and window size. Headless import/export tooling is not evidence of GPU rendering.

The UI is a 2D canvas over a 3D world. World lighting, reflections and antialiasing apply to the court and athletes. The interface stays outside the world color finish; there is no reason to apply 3D fog, GI or temporal accumulation to its text.

## Implementation decisions

- Color palettes and the generated colored foliage texture use `source_color`. Linear grayscale vertex multipliers remain data. Approximate gamma conversion in sky/water and unconverted ball/outline palettes are removed. The custom skin light no longer multiplies albedo twice and can receive ambient illumination.
- The world-only brush blur is replaced by a single-sample print color finish. Authored cloth folds, matte materials, derivative-filtered grain, banded leaf/skin lighting and silhouette ink remain deliberate art techniques. Subpixel jersey knit noise is removed.
- Foliage uses mipmaps and alpha-to-coverage. Its color texture is decoded once; the old extra brightness multiplier is removed. Opaque net strands retain their geometry and physical occlusion.
- Ocean water uses lit opaque shading, subdued wave normals and sky reflection. It does not sample screen depth or pretend camera distance is water depth. No legacy NDC conversion, transparent refraction path or redundant unshaded-water implementation is retained. The sea keeps a deliberate fog exemption to retain coastal blue under the authored atmospheric palette; this is an artistic choice, independent of renderer compatibility.
- Seasonal sky radiance is cached. Imperceptibly slow cloud drift previously forced procedural cubemap updates every frame. Foliage, water, athlete and ball animation continue normally.

### First review and corrections

The first exact-state comparison used frame 300 of ordinary season-one play: 5.0 simulated seconds, identical camera transform, ball position/height, and all six player dictionaries at 1280×720. Both independent visual and rendering reviewers rejected it: pale skin, washed-out sky/sea, and noisy soft-shadow edges were concrete regressions despite clearer foliage/net edges. Those failed captures are retained in the working evidence.

The sky issue exposed a baseline double conversion: runtime `Color` uniforms were already linearized, then the sky shader applied another approximate gamma transform. The corrected shader uses one conversion and newly authored seasonal colors instead of restoring that compensation. Complexion colors and ambient/direct-light balance were retuned; high-angular-distance PCSS was replaced for the next review with filtered shadows. The final matched coast, evening harbor and overcast garden views passed both independent static reviews. A small skin-only warm-neutral palette adjustment then removed the remaining olive cast. Scenery batching also now preserves per-mesh shadow policy, so decorative sea foam does not acquire shadows when merged.

### Initial feature experiments (not final benchmarks)

Single-instance native trials exercised SDFGI, SSIL, SSR, a distant FogVolume, TAA and MSAA/filtered shadows. The first candidate and SSIL/SDFGI/fog trials sustained the 60 FPS cap in short warmed samples. SDFGI increased engine-accounted video memory from about 320 MiB to 699 MiB and process residency to about 927 MiB, with a first-enable stall longer than the review console's ten-second timeout. It introduced deeper, cooler indirect shading, but moving athletes, effects and wind crowns had to be excluded from its static field. These measurements alone do not establish acceptable venue-switch behavior.

SSR and TAA samples crossed a defeat transition, so their frame-time summaries are not comparable active-play benchmarks. Enabling an effect and reaching the frame cap is not a visual acceptance criterion. First-pass volumetric fog also weakened backdrop separation; later selection is based on matched revised views and movement.

The Metal GPU-timing query returned zero despite measurement being enabled. This is unavailable data, not a zero-cost frame. An engine texture-memory counter also underflowed; its invalid value is not used. OS RSS is recorded separately, and the final comparable measurements restart each candidate to avoid retained allocations from previous feature trials.

## Matched views and performance

The before images show the newer partial Forward+ iteration, **not** the older 2D Compatibility build. Camera, court location, generated venue, season, full-motion setting, default inputs and resolution match. Captures use frame 300 at fixed 60 Hz (5.0 simulated seconds), with the same shader clock in disposable capture copies. Their complete camera/ball/player state dictionaries match. This isolates presentation changes without attributing the inherited 3D rebuild to the migration.

| Lighting / venue | Before | After |
| --- | --- | --- |
| Coast morning, season 1 | [Before](evidence/forward-plus/matched/baseline-coast-300.png) | [After](evidence/forward-plus/matched/final-season-1-300.png) |
| Harbor dusk, season 6 | [Before](evidence/forward-plus/matched/baseline-season-6-revised-300.png) | [After](evidence/forward-plus/matched/final-season-6-300.png) |
| Gardens overcast, season 8 | [Before](evidence/forward-plus/matched/baseline-season-8-revised-300.png) | [After](evidence/forward-plus/matched/final-season-8-300.png) |

Measured September 6, 2026 on an AC-powered MacBook Pro, Apple M3 Max, 36 GiB unified memory, macOS 26.5.2, Godot 4.7.2 native Metal Forward+. Default **1280×720**, 60 FPS cap, ordinary 1× gameplay, full motion. Each of six runs started a fresh process, warmed through 15 simulated seconds, then recorded 30 wall-clock seconds / 1,800 frames of an active match. No screenshots or movie writing occurred during measurement. Other game processes were exited or suspended; an exclusive runtime lock and process inventories are retained.

| Build / venue | Mean ms | p95 ms | p99 ms | Worst ms | Frames >20 ms | Mean / peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Before coast | 16.667 | 17.545 | 18.589 | 19.979 | 0 | 472.5 / 472.6 |
| After coast | 16.667 | 17.891 | 19.064 | 21.136 | 4 | 530.9 / 530.9 |
| Before harbor | 16.666 | 17.189 | 18.966 | 19.936 | 0 | 493.9 / 494.0 |
| After harbor | 16.666 | 17.403 | 18.826 | 20.971 | 1 | 499.8 / 499.8 |
| Before gardens | 16.666 | 17.497 | 18.680 | 19.606 | 0 | 508.6 / 508.8 |
| After gardens | 16.666 | 17.482 | 18.855 | 22.460 | 2 | 515.4 / 515.5 |

All runs average approximately 60 FPS, with no measured frame above 33.334 ms. This is not a promise of exactly 16.67 ms every frame or evidence of unused GPU capacity. The final coast costs about 58 MiB additional process residency; harbor and gardens cost about 6–7 MiB. The cap prevents meaningful speedup claims. GPU-query data is unavailable on this Metal build. These warmed samples exclude initial shader compilation and venue construction; export/restart and transition behavior are recorded separately in the runtime review.

A zero-RSS process-exit sample is unavailable and excluded from RSS means. Raw RSS `elapsed_s` values use the monotonic clock, not time since launch.

Raw samples, measurement commands, RSS observations and process inventories are under [performance](evidence/forward-plus/performance/). Disposable capture/measurement sources are archived under [reproduction](evidence/forward-plus/reproduction/); they contain no assertions, bots or pass/fail tests and are excluded from the exported game by `evidence/.gdignore`. Historical failed experiments remain under [experiments](evidence/forward-plus/experiments/). No automated tests were created.

## Official references

Version-specific primary references used for the implementation:

- [Godot 4.7 renderer overview and fallback](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html)
- [Actual renderer and driver queries](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html)
- [Spatial shader color, lighting and alpha antialiasing](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html)
- [Sky shader radiance update rules](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/sky_shader.html)
- [MSAA, TAA, FXAA and SMAA](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html)
- [SDFGI and procedural/dynamic geometry](https://docs.godotengine.org/en/4.7/tutorials/3d/global_illumination/using_sdfgi.html)
- [Volumetric fog and temporal artifacts](https://docs.godotengine.org/en/4.7/tutorials/3d/volumetric_fog.html)
- [SSAO, SSIL and SSR](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html)
- [Forward+ reversed-Z depth reconstruction](https://docs.godotengine.org/en/4.7/tutorials/shaders/advanced_postprocessing.html)

Cozy Sora's local `shared/atmosphere.gd` provided useful two-cascade shadow and ambient-occlusion precedents; its derivative-filtered procedural patterns were already adapted by the newer baseline. Its approximate-gamma ocean and blanket fill lighting were not copied as migration solutions. Spike Season has no runtime dependency on that project.
