# Last Cast — Forward+ verification checkpoint

Stopped at the user’s request after the rendering migration, matched visual review, measurements and partial exported-app play. Full fishing completion and save/relaunch verification remain unfinished.

Migration from `647a6e8f7`, built in the isolated `lastcast-forward-plus` worktree. The original brief, fishing-boat reference, [original verification](VERIFICATION.md), and [previous polish findings](POLISH_VERIFICATION.md) informed this pass. Gameplay remains procedural 3D with a separate CanvasLayer interface. No automated tests were created.

## Renderer and ownership

Godot 4.7.2 is required for the verified setup. Development and desktop exports select Forward+; automatic OpenGL fallback is disabled. A release-safe startup guard checks the actual rendering method and RenderingDevice before loading a save. Startup prints method, driver and GPU. A command-line renderer override cannot silently run a different game presentation.

All resources remain local to Last Cast. Cozy Sora informed contact shading, shadow filtering/cascades and foliage antialiasing. Its opaque stylized ocean and post-process brush were not copied: Last Cast needs a visible seabed and sharp fishing instruments.

## Rendering changes

- Shader `source_color` inputs are converted by Godot once. Removed extra gamma powers from plaster, water, seabed, sky and foliage. MultiMesh colors now have one explicit sRGB-to-linear upload path. Timber/roof/cloud/eelgrass palettes use color uniforms, replacing approximate gamma exponents. Already-linear terrain and StandardMaterial vertex colors remain linear.
- Water reconstructs Forward+ reverse-Z depth with the inverse projection matrix and uses optical thickness for absorption. Removed world-Z shoal approximation, unconditional transparent depth writes, and unnecessary planar-water subdivision (the sheet now uses two triangles). The sea draws before above-water wake/cues in every camera orientation. Replaced the wake's StandardMaterial alpha path with a small unshaded shader that clamps interpolated alpha: MSAA's subpixel interpolation had produced negative alpha and dark foam specks. Matching lossless captures confirmed the correction; depth testing remains enabled.
- Retained intentional painterly crown normals, procedural material noise, planar normal waves, seabed, restrained caustics, fish-school cues and boat buoyancy. These have artistic/gameplay uses independent of Compatibility.
- Foliage uses source-color texture sampling and MSAA alpha-to-coverage. Directional shadows use a 4096 atlas, blended cascades, smaller normal bias and high-quality fixed soft filtering (blur 1.6). Local SSAO grounds contacts. The 2D interface is not processed by 3D lighting or fog. Corrected sky and timber palettes retain the sunny pastel direction without reintroducing gamma compensation.

## Feature evaluation

Exploratory variants are temporary runtime adjustments, not parallel implementations shipped in the game.

| Feature | Observed result / decision |
| --- | --- |
| SDFGI | Four cascades / 0.3 m cells were tried at energy 0.6, then 1.1. The corrected trial excluded the moving actor, foliage, water and weather from occluder contribution, retaining generated static scenery. Shop recesses lost detail; the initial allocation trial rose from about 276 MiB to 630 MiB of renderer-reported memory. Not selected: the open harbor gained too little for the darker recesses and additional memory/update work during region rebuilds. This rejects the tested configuration, not every possible GI tuning. |
| VoxelGI / LightmapGI | Not selected: the world is generated and rebuilt at runtime, with no authored bake assets. SDFGI was the applicable dynamic candidate. |
| Volumetric fog | Density 0.008 / length 80 m veiled the coast and lighthouse. A second trial at 0.0015 / 110 m, sky affect 0.1, replaced regular fog and kept the foreground clear but exposed a hard horizon. Both disabled temporal reprojection to avoid moving-camera trails. Existing restrained regional fog better preserves the intended horizon and fishing clarity. |
| SSIL | Radius 2 m / intensity 0.35 was compared again after correcting materials. The additional shading was subtle and did not justify another screen-space pass over selected SSAO. Disabled. |
| SSR | Runtime comparison showed little useful gain on the transparent sea. Godot's screen-space reflection pass operates on opaque surfaces; it cannot supply reliable reflected boats/coast to this transparent water. Disabled. Sky reflection and procedural wave normals remain. |
| Reflection probe | Considered, not selected or benchmarked: a static harbor cubemap would project local objects inaccurately across the 700 m plane and freeze lighting at capture time; continuous recapture adds work during sailing and daylight changes. No unused probe resource was added. |
| Directional soft shadows | A 0.65° contact-hardening sun produced visible grain on the curved hull. Replaced with stable fixed filtering, a 4096 atlas, blended cascades and restrained bias. No PCSS variant remains. |
| TAA / MSAA | Matched 1.5 rad/s boat-camera orbits showed TAA blurring shop signs, hull edges and sailor detail. Selected 4× MSAA plus foliage alpha-to-coverage; no temporal reconstruction/history trails. The separate CanvasLayer interface remains crisp. |
| Glow / DOF / automatic exposure | Not selected: brighter fishing cues, blurred scenery, or changing exposure would work against the reference's calm materials and consistent instrument readability. |

## Method and evidence

Measured on Apple M3 Max / 36 GiB unified memory / macOS 26.5.2, Godot 4.7.2. Design coordinates remain 1440×900; the default window and independently checked native PNG framebuffer are **1280×800**. VSync was enabled, normal pace was 1×, and only one game was active. Other game sessions were suspended during measurement.

Each renderer started in a fresh process with the same isolated save. The shore warmed for 30 seconds, then sampled for 30; the boat warmed for 30 seconds, then sampled for 30. Two further 30-second samples used normal throttle/steering with a 1.5 rad/s camera orbit, and an active sunset from approximately 40 to 10 seconds of remaining daylight. Frame data is chronological wall-clock intervals; Godot's `TIME_PROCESS` is a separate CPU monitor, not GPU time. No recording or image readback ran during these samples. RSS was read before any image capture. Timing workloads are equivalent; buoyancy introduces small (roughly 5–10 cm) camera-height phase differences, unlike the exact matching visual replay.

| Scene | Before mean / p99 (ms) | Forward+ mean / p99 (ms) | RSS before → after (MiB) |
| --- | --- | --- | --- |
| Shore | 16.667 / 17.422 | 16.667 / 19.034 | 486.5 → 566.3 |
| Boat | 16.676 / 20.613 | 16.667 / 19.263 | 487.5 → 566.6 |
| Sailing + orbit | 16.960 / 23.752 | 16.677 / 18.862 | 497.9 → 568.5 |
| Active sunset | 16.667 / 21.498 | 16.667 / 18.372 | 499.1 → 568.9 |

Forward+ averaged approximately 60 FPS in every sample. Its worst interval was 33.176 ms during sailing; no sampled interval exceeded 33.333 ms. This is near-60 performance, not a promise that every frame meets a strict 16.667 ms deadline. The shore's p99 worsened from 17.422 to 19.034 ms; boat, sailing and sunset tails improved. Compatibility's sailing sample included a 166.029 ms stall. The final candidate's process RSS was about 70–80 MiB higher. Renderer-reported allocations rose from about 55.5 MiB to 275.7–276.0 MiB; these counters overlap process/unified memory accounting and must not be added to RSS.

[Evidence and raw samples](evidence/forward-plus/README.md) include five lossless before/after pairs. Their recorded camera transforms, actor positions, seed, daylight, season, region and resolution match exactly. An external fixed 60 FPS replay was used to inspect walking, steering and camera orbit; the accepted native frames are committed here. MovieWriter encoding speed is not a performance result; final video packaging was not completed before the stop request. Ordinary exported-app play supplies the separate gameplay check. Additional controlled native views cover late sunset and both other regions in winter. Exploratory configurations and diagnostic scripts remain outside the project; no automated tests or debug scenes were added.

## Desktop export and independent review

The final macOS export completed with Godot 4.7.2's matching templates, ad hoc signing, and local assets only. A first export exposed the arm64/universal requirement for ETC2/ASTC imports; that valid Forward+ platform setting was retained alongside S3TC/BPTC. The export excludes evidence, documentation, build files and override files; the temporary verification `override.cfg` was removed from the checkout.

Running the exported binary from `/tmp` with `--rendering-method gl_compatibility` printed the actual OpenGL renderer, then refused startup with exit code 1. The original save SHA256 remained `afb82228fa040b6cf5e2a75ecceb53226ee178c0e67d56205769960e98f2b1d5`. The standalone export subsequently loaded the existing 344-shell earned profile. The independent reviewer verified boarding, forward travel, camera orbit, wake visibility, summer expedition selection, Quick Spool and an actual Harbor Bream cast/presentation. Focus pace was used for input latency. The user stopped the review during presentation; hooking, a completed retrieve/landing, and save/relaunch were not verified in this pass. The original save and voyage log were restored afterward.

Three independent agents reviewed rendering/removal, visuals, and runtime/performance. Their substantive findings drove the restrained caustics, darker timber, revised sky/water palette, fixed shadow filtering, explicit sea ordering and clamped wake alpha. The final matched views and sunset/winter samples passed visual re-review. The source/removal review and independent metric audit passed; the exported fishing/save pass was interrupted by the user’s stop request. The casting screenshot did not receive a final independent visual re-review.

## Limits

The measured scope is four 30-second workloads on this Mac, not a long thermal soak or a guarantee for other GPUs. Windows/Linux exports and lower-end hardware were not verified. The palette is softer and more muted than the former Compatibility image; the independent visual review accepted this alongside improved material detail and depth. Existing faceted scenery and the distant regional haze remain part of the procedural art, rather than matching the supplied reference's geometric detail. MSAA preserves readable moving signs and rigging, but cannot eliminate every subpixel foliage shimmer. The world uses sky reflections; transparent water does not reflect nearby boats/coast through SSR. The 2D CanvasLayer interface receives none of the 3D lighting/depth effects.

## Official Godot 4.7 references

- [Renderer architecture and native Metal](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html)
- [Fallback setting](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-rendering-rendering-device-fallback-to-opengl3) and [actual runtime rendering method](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html#class-renderingserver-method-get-current-rendering-method)
- [Shader color handling](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html) and [depth reconstruction](https://docs.godotengine.org/en/4.7/tutorials/shaders/advanced_postprocessing.html)
- [Sky reflection update modes](https://docs.godotengine.org/en/4.7/classes/class_sky.html)
- [SDFGI](https://docs.godotengine.org/en/4.7/tutorials/3d/global_illumination/using_sdfgi.html), [volumetric fog](https://docs.godotengine.org/en/4.7/tutorials/3d/volumetric_fog.html), and [screen-space environment effects](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html)
- [3D antialiasing](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html) and [sun angular distance](https://docs.godotengine.org/en/4.7/classes/class_light3d.html#class-light3d-property-light-angular-distance)
