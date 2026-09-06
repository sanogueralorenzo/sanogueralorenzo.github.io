# Rendering review

Reviewer: rendering audit agent, 2026-09-06. This is a demanding source and image review of the Forward+ rendering work against the preserved newer 3D baseline. The reviewer also implemented the separately scoped startup/launcher enforcement and export presets, so those changes are not represented as independently reviewed by their author. No automated tests were created or run.

## First-pass findings and disposition

1. **Invalid alpha antialiasing built-in — corrected in source.** The first foliage shader wrote `ALPHA_TEXTURE_COORD`; Godot 4.7 declares `ALPHA_TEXTURE_COORDINATE`. The corrected shader now supplies pixel coordinates from UV and texture size, with alpha-to-coverage enabled and an antialiasing edge below the scissor threshold. Native foliage rendering still needs the final evidence check.
2. **Obsolete shader companion — removed.** The replaced 37-sample painter shader and its orphaned UID are absent. A one-sample world color finish replaces the screen blur. The screen-space UI remains outside that finish.
3. **First matched images rejected.** The initial coast frame-300 pair had identical gameplay/camera state but visibly paler skin, light cyan sky, gray sea and stippled directional shadows. Improved net/foliage edge clarity did not compensate for those regressions.
4. **Sky color cause established.** The baseline passed runtime `Color` values, which Godot already converted to linear, then applied an additional approximate gamma transform in the shader. Removing that second conversion is correct but exposes a palette previously authored around the defect. The revised implementation retains one conversion and authors richer seasonal palette values instead. The first skin shader also multiplied albedo twice in custom direct lighting; Godot multiplies accumulated diffuse light by albedo afterward. Its corrected contract is retained while skin palettes are retuned explicitly.
5. **Unnecessary radiance updates — corrected in source.** The original very slow cloud drift used `TIME`, forcing cubemap generation/filtering each frame. The revised seasonal sky is static between palette changes, allowing radiance caching. Water and foliage retain their motion.
6. **Noisy soft shadows — implementation revised, visual result pending.** The initial angular-distance PCSS produced visible stippling without temporal accumulation. Current source uses angular distance zero, two blended cascades, a 65 m limit, 4096 atlas and filtered blur 1.6. These settings need ordinary-motion confirmation across the season light directions.

## Current source assessment

The initial follow-up found no additional definite source defect. A subsequent complete shadow-ownership audit found the pending issue below. This is not final visual or performance approval.

- Skin and foliage retain intentional broad painted lighting bands; custom diffuse light is not multiplied by albedo twice. Color texture/uniform inputs and linear grayscale vertex multipliers have distinct handling. Palette corrections do not restore approximate gamma or blanket fill-light compensation.
- Ocean shading is now lit and opaque, with low-amplitude world-space wave normals transformed to view space, restrained specular response and rougher distant reflections. It samples no screen/depth texture, so no renderer-specific depth reconstruction or transparency sorting workaround is needed. Its retained fog exemption is explicitly documented as an artistic choice; final sea-to-headland continuity remains a visual check.
- Inverted-hull ink, derivative-filtered procedural grain, authored cloth folds and thin fountain/ball-effect transparency remain purposeful techniques. They are not obsolete merely because Forward+ offers other effects.
- Current AA is 4× MSAA plus SMAA. Foliage coverage uses the MSAA samples. This is structurally appropriate for the stylized world, but evidence must show that the combination is worth its cost and does not blur the ball or net. Cached portrait viewports have their own MSAA settings.
- SSIL intensity 0.25/radius 2.5 is provisional. It needs comparison under identical conditions, especially camera retreat, near athletes against bright clay, and venues with more occlusion. Enabling it is not itself proof of improved lighting.
- The project has no runtime reference to Cozy Sora or a parent project's resources. The implementation remains independently runnable.
- Review timing records frame intervals and reports unavailable GPU timing as null. The observed invalid texture-memory counter is normalized to null. These are not complete GPU-residency measurements; comparable process RSS and fresh launches are required for memory conclusions.

## Subsequent source finding

**Foam shadow ownership — corrected.** `coast.gd` explicitly disables shadow casting on foam meshes, but the initial `batch_static()` grouped only by material and created replacements with default shadow casting enabled. The new lit ocean could expose foam shadows that the former unshaded ocean did not show. Reinspection confirms batches are now keyed by material and integer shadow mode, and every replacement receives that mode explicitly. The implementation owner reports the corrected native source compiled cleanly.

The remaining fountain streams are intentional thin, translucent, unshaded background geometry outside the court. Their continued existence is not evidence that the removed unshaded ocean implementation survives. Final native views still need to establish that they do not exhibit distracting transparency artifacts.

## Final source and matched still review

Reviewed `final-season-1-300.png`, `final-season-6-300.png` and `final-season-8-300.png` directly against `baseline-coast-300.png`, `baseline-season-6-revised-300.png` and `baseline-season-8-revised-300.png`. The paired capture JSON dictionaries match exactly for all three pairs, including camera, frame, player state and ball state. Images are 1280×720. The captures were supplied by the implementation owner; this reviewer did not launch a concurrent game.

**Source and still-image migration review passes.** Earlier pale-skin/gray-sea regressions are corrected sufficiently to preserve the stylized summer identity. Skin has distinct warm complexions rather than the first candidate's nearly cream faces; coastal water is visibly blue again. The seasonal sky remains differentiated, including the lavender/peach harbor and overcast gardens. Foliage has clearer individual leaves and stronger canopy depth, and net, shirt numbers, edges and court markings remain readable. The reduced blur improves small geometry without affecting the cream UI's crisp text. Softer foliage shadow boundaries avoid the first candidate's broad PCSS noise. Some fine stippling remains visible in shadowed surfaces and must still be judged in motion; a still image cannot establish shimmer or temporal stability.

The final images remain a simple procedural stylized 3D adaptation; this review does not claim that the historical illustrated-reference fidelity gap has disappeared. It approves the rendering migration's scoped static improvement and preservation of scene readability.

The supplied six-entry `performance-summary.json` records separate baseline/candidate runs in seasons 1, 6 and 8, each with 1,800 samples from 15–45 seconds of active 1× gameplay. Both variants average approximately 16.667 ms. Candidate p95 intervals are 17.891/17.403/17.482 ms and p99 intervals 19.064/18.826/18.855 ms; worst intervals are 21.136/20.971/22.460 ms. Candidate runs contain 4/1/2 intervals over 20 ms and none over 33.334 ms, versus zero over 20 ms in the baseline. These results support a stable capped 60 FPS target in the observed windows, with a small increase in isolated frame-time excursions; they do not establish greater GPU headroom.

Candidate mean process RSS is approximately 531/500/507 MiB versus baseline 472/494/509 MiB. The coast therefore costs about 58 MiB more mean RSS; harbor changes little and gardens is comparable. Reported video-memory counters increase roughly 44 MiB in each venue. GPU timing is unavailable, and the baseline texture counter is invalid/null, so those counters cannot establish exact residency or GPU frame cost. Motion and final exported-app verification remain pending; no unconditional whole-migration approval is given here.

## Remaining approval gates

Inspect the corrected coast/harbor/gardens views and moving gameplay; check ball, fingers, foliage, net edges, shadow stability, skin complexion, ocean horizon and crisp UI. Review measured feature comparisons and final fresh-launch frame-time/RSS results. Confirm final desktop export success and native exported-app renderer/startup behavior. The earlier successful enforcement check and preliminary macOS export do not certify the final rendering revision.

For a valid SDFGI experiment, exclude athletes, ball effects and moving foliage from GI contribution: Godot 4.7 defaults geometry to Static. Regenerate after venue replacement has removed old geometry. This requirement applies to evaluating SDFGI even if the final decision is to reject it.

## Primary references

- [Godot 4.7 spatial shader contract](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html)
- [Godot 4.7 shader built-in declarations](https://github.com/godotengine/godot/blob/4.7-stable/servers/rendering/shader_types.cpp)
- [Forward+ diffuse/albedo composition](https://github.com/godotengine/godot/blob/4.7-stable/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl)
- [Sky material upload](https://github.com/godotengine/godot/blob/4.7-stable/servers/rendering/renderer_rd/environment/sky.cpp), [material uniform conversion](https://github.com/godotengine/godot/blob/4.7-stable/servers/rendering/renderer_rd/storage_rd/material_storage.cpp), and [runtime Color conversion](https://github.com/godotengine/godot/blob/4.7-stable/servers/rendering/storage/variant_converters.h)
- [Sky radiance update rules](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/sky_shader.html)
- [3D antialiasing tradeoffs](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html)
- [Geometry GI defaults](https://docs.godotengine.org/en/4.7/classes/class_geometryinstance3d.html)
