# Forward+ migration — 6 September 2026

Built in `squirrelswoop-forward-plus`, based on repository commit `0e94f6625` (Squirrel Swoop refinement `869a11537`). Godot **4.7.2.stable.official.ed1daf0bf**, macOS **26.5.2**, Apple M3 Max, **36 GiB RAM**. No automated tests were created. Verification uses the actual rendered game, discrete manually selected console/key controls, viewport captures, and desktop exports.

## Intent and scope

Read the original creation and refinement objectives from the prior **Build Squirrel Swoop game** task, the supplied [visual target](../visual-target.png), [refinement findings](../refinement/REFINEMENT.md), and independent visual/flight reviews. Preserve warm chestnut fur, olive moss and needles, cool forest shadows, the steep continuous meadow/stream/woods mountain, and readable hazards. This is a rendering migration, not new terrain or flight design. Flight physics, input, camera, progression, collision, seeded placement, scoring, menus, and the save format remain unchanged. Crown render geometry loses its opaque filler wedges; both needle sprays remain, with no random-number sequence change.

The game is procedural 3D with a separate CanvasLayer HUD. Forward+ effects improve the world; they do not improve or blur the 2D interface. All resources remain local to this game. The reference is excluded from runtime assets.

## Renderer and replacement audit

- Project requires `forward_plus`, declares Godot 4.7 / Forward Plus, removes the old mobile Compatibility override, and disables `rendering_device/fallback_to_opengl3`. All desktop presets inherit this configuration. Startup queries the actual RenderingServer method/driver/GPU and exits nonzero before loading saves or constructing the mountain if the method is wrong.
- Exact sRGB decoding is centralized in `pigment.gdshaderinc` for authored shader palettes and vertex pigments. The pine texture retains `source_color` and is not decoded twice. StandardMaterial vertex colors retain `vertex_color_is_srgb=true`. Sky conversion uses the exact transfer instead of approximate gamma 2.2. Water vertex red is slope data and remains unconverted.
- Deleted the full-screen brush shader, its UID, and installation nodes. It had partly substituted for AA after a Compatibility card-edge defect. Native MSAA now handles geometry, alpha-to-coverage handles pine needles, and procedural pigment/derivative-filtered fur preserve painterly detail. The old pass softened fine details and read the screen repeatedly. Its shadow tint/vignette are not retained alongside the replacement.
- Deleted foliage's screen-coordinate visibility dither and manual needle discard. Native alpha coverage preserves the intentional camera-to-squirrel foliage opening; solid wood remains visible. Camera reveal does not punch holes in shadow maps. The world-position varying follows vertex sway.
- The independent close-canopy movement review exposed nearly black triangular filler cores beneath the needle sprays. All reviewers identified these as a substantive defect. Deleted the four filler triangles per branch and the obsolete negative-UV shader branch. They had no collision role or random-number calls. Corrected close flight and distant-crown captures check the resulting density; earlier motion evidence is explicitly labeled before this correction.
- Retuned shadow bias against visible terrain hatching; simply copying a small bias from Cozy Sora was inadequate on this steep procedural slope. Filtered four-cascade directional shadows remain. The old shadowless fill is replaced by blended sky irradiance and restrained cool ambient color, retuned after reviewers found an unreadably dark squirrel.
- Water replaces painted glints with world-space ripple normals transformed into view space, dielectric response, sky reflections, and rough banks. It stays opaque: the existing stream is only 7.5 cm above terrain. There was no depth sampler to repair. Invented deep-water absorption/refraction would not match this geometry; no OpenGL depth remap, screen texture or sorted transparency path remains to maintain.

## Feature evaluation

| Feature | Decision and evidence |
| --- | --- |
| 4× MSAA + pine alpha coverage | Selected. Keeps fine silhouettes without history blur. Coverage thresholds `.20 + .14` retain the prior `.34` needle contour. UI is outside 3D AA. |
| TAA | Rejected after still and moving trials: smoother shadow noise, but noticeably softened needle/fur detail and tree outlines at 1280×800. See [TAA still](trials/woods-taa-fog.png) and [moving frame](trials/taa-motion.png). No claim that this brief trial rules out every possible ghosting case. |
| Directional PCSS, angular distance .5° | Rejected: broad penumbrae produced visible stipple without TAA; the TAA combination sacrificed clarity. [Initial trial](trials/after-woods-initial.png). Selected high-quality PCF, blur 1.4, four blended cascades, 4096 map, bias .2 / normal bias 1.4. [Bias comparison](trials/woods-bias14.png). |
| SSAO | Selected at radius .8, intensity .7, power 1.2, detail .4. Restrained contact grounding around rocks/roots. Disabling AO did not remove shadow hatch, so it was not used to conceal that defect. |
| Volumetric fog | Selected at density .0012, length 100 m, with reduced ordinary fog density .0015 for distant continuity. Low density adds filtered atmosphere while retaining near hazards. Temporal reprojection is disabled to avoid history trails during fast banking. Higher .003/.002 trials added too much warm veil. |
| SDFGI | Evaluated with two cascades, .5 m cells, full vertical scale, static sunlight, only static terrain/wood/rocks contributing, and moving character/foliage/backdrop/water excluded. The streamed neutral descent reached the same collision at 941.291 m; a 595.85–941.29 m window measured p50 16.662 / p95 18.851 / max 26.448 ms, RSS 539–543 MiB. Performance alone did not disqualify it. [Woods study](trials/woods-gi.png) added green/cyan lighting and darker chestnut without enough useful bounce structure; rejected. The temporary classification/bootstrap implementation was not shipped. |
| VoxelGI / baked lightmaps | Rejected architecturally: the mountain streams procedural geometry during play. VoxelGI needs a bounded bake volume; lightmaps need prepared geometry/UVs. SDFGI was the relevant dynamic trial. |
| SSR | Rejected after matched stream and banking review: near-identical result to sky reflections on this narrow rough sheet, with screen-edge/offscreen limitations and extra work. [Without](trials/stream-no-ssr.png), [with](trials/stream-ssr.png). |
| SSIL | Rejected: negligible useful separation in the [woods trial](trials/woods-ssil.png). Ambient balance and SSAO gave the required readability. |
| Sky radiance | Incremental processing selected for slowly drifting procedural clouds. Spreads high-quality radiance work across frames. The final sky is paler than the original. A separate background-energy .65 versus 1.0 trial made it grayer and dulled water response without restoring blue saturation; all three visual observers preferred retaining 1.0. This remains an artistic tradeoff, not an across-the-board color-fidelity improvement. |
| Glow, depth of field, temporal upscaling | Not needed for this art direction: no emissive spectacle, intentional focus on upcoming hazards, and native-resolution geometry clarity. |

Cozy Sora supplied useful examples of restrained SSAO/contact grounding, filtered sun shadows, separated HUD/post layers, and locally owned atmosphere. Its settings were not copied wholesale; its painted-ocean and fog-quad techniques were not appropriate replacements here.

## Matched views

All comparison PNGs are 1280×800 actual viewport captures, with unchanged camera code/FOV, exact seed, location, and height, and the same fixed sun direction/color/energy. Studies are explicitly staged and labeled `STUDY`; they are not claimed descents. Generation must report `pending:0` and `building:false` before capture. Cloud, particle, and foliage animation phases are not locked; lighting conditions are fixed and geometry is seeded. Before captures use the original Compatibility game, not an override of the migrated shaders.

| Scene | Before | Forward+ |
| --- | --- | --- |
| Summit, seed 482193 | [Before](comparison/before-summit.png) | [Forward+](comparison/after-summit.png) |
| Woods, seed 482193, d650 / x68 / height6 | [Before](comparison/before-woods.png) | [Forward+](comparison/after-woods.png) |
| Deep woods, seed 482193, d2300 / x76 / height5.5 | [Before](comparison/before-deep-woods.png) | [Forward+](comparison/after-deep-woods.png) |
| Woods, seed 915772, d1150 / x70 / height6 | [Before](comparison/before-woods915772.png) | [Forward+](comparison/after-woods915772.png) |
| Stream, seed 752041, d820 / x0 / height6 | [Before](comparison/before-stream.png) | [Forward+](comparison/after-stream.png) |

## Performance and runtime evidence

See the independent [visual critique](INDEPENDENT-VISUAL.md), [final rendering audit](INDEPENDENT-RENDERING-FINAL.md), and [runtime/export review](INDEPENDENT-FLIGHT.md). The earlier [implementation audit](INDEPENDENT-RENDERING.md) discloses its reviewer's participation in the pigment/foliage changes; the final rendering reviewer authored none of the implementation. Measurements exclude screenshot writes, staged jumps, initial population and shader compilation. Godot static memory differs from operating-system RSS. A 1800-frame rolling window is reported for the matched source runs; first launch/loading stalls are not hidden in sustained-flight statistics.

Fresh isolated Compatibility neutral seed752041: p50 **16.689 ms**, p95 **18.148 ms**, max **26.531 ms**, final 1800 frames, 941.291 m collision, RSS **360.8–391.5 MiB**. Earlier shared-load baseline was much slower (26.093/38.094/87.010 ms); it is not used to claim a migration speedup. During isolated windows the other preexisting game review processes were suspended through coordination with the other active migrations. This is a shared verification machine, not a universal GPU guarantee.

Fresh isolated final Forward+ neutral seed752041, after the canopy correction: p50 **16.655 ms**, p95 **18.814 ms**, max **23.202 ms**, final 1800 frames, the exact same 941.291 m collision, speed, position, three close passes and 1854.025 score. RSS **474.7–487.9 MiB**. The median remains near 60 FPS; p95 is higher than the baseline's 18.148 ms, and this is not a locked-60 result. End-of-run RSS is about **96 MiB higher** than the baseline. An earlier Forward+ run before the canopy correction measured 16.651 / 17.987 / 21.961 ms and 409.3–432.4 MiB RSS. These differences between runs do not isolate the cost of individual effects or establish an indefinite memory trend; no speedup or memory improvement is claimed.

Independent standalone play reached **3,216.59 m** from the summit, exercised banking, pitch, dive/recovery, route crossings, collision, pause/retry, and preserved records plus all four settings across restart. Its last long-flight window measured 16.670 / 19.181 / 22.660 ms. This long run preceded the final visual-only core removal; the corrected source repeated the exact neutral descent, all five matched views and close-canopy motion, and the rebuilt standalone app repeated woodland flight. Source hashes and revision labels separate the evidence. The black wedges are resolved; fine needle patterns and shadow variation remain. A small phase-dependent cloud seam is visible in the final summit capture, consistent with the inherited sky shader's longitude wrap. Sparse motion captures do not certify every transient shimmer event or physical-controller feel.

Windows x86_64 and Linux x86_64 release exports also completed without logged errors or warnings using the matching 4.7.2 templates. They were built on macOS and have not been executed on their native operating systems. The macOS app was independently re-exported, copied outside the repository, and passed strict code-signature verification; native play is recorded in the independent flight report.

## Official references for installed Godot 4.7

- [Rendering settings and driver fallback](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-rendering-rendering-device-fallback-to-opengl3)
- [Spatial shader color, coverage and shadow-pass semantics](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html)
- [3D antialiasing](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html)
- [Environment, SSAO, SSIL, reflections and tonemapping](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html)
- [Volumetric fog and reprojection](https://docs.godotengine.org/en/4.7/tutorials/3d/volumetric_fog.html)
- [SDFGI and fast-camera/streaming limitations](https://docs.godotengine.org/en/4.7/tutorials/3d/global_illumination/using_sdfgi.html)
- [Sky processing modes](https://docs.godotengine.org/en/4.7/classes/class_sky.html)
- [RenderingDevice depth reconstruction](https://docs.godotengine.org/en/4.7/tutorials/shaders/advanced_postprocessing.html)
