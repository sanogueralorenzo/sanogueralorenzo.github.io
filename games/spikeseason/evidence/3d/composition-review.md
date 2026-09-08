# Spike Season: independent 3D composition review

Fresh review for the genuine Godot 4 3D rebuild. Previous 2D approvals do not apply. Inspected the approved `volleyball-art-direction-3v3.png`, an ordinary live 2D rally captured read-only from port 45901 (`baseline-3d-comparison.png`), and the local Cozy Sora 3D implementation. No game source was edited; no gameplay input was sent to the parent's baseline session; no automated tests were created.

## What the baseline fails to reproduce

The 2D baseline is a flat illustrated tableau. Its court trapezoid and explicit sprite scaling create some size difference, but athletes remain front-facing planar figures, architecture is a mostly orthographic facade stack, and shadows are painted approximations. The target's appeal depends on actual depth: a low spectator viewpoint, large near-side athletes, smaller distant defenders, an elevated net, diagonal athletic poses, tree-canopy shadows crossing the ground, a cliff down to the sea, and buildings receding uphill. A true 3D rebuild must make those relationships emerge from shared world coordinates, a perspective camera, lit meshes, and physical occlusion. Placing the current illustration on a plane or replacing figures with camera-facing cards would not satisfy the goal.

## Composition targets

The percentages below are visual estimates from the approved 1670×940 illustration, not claims of recovered camera calibration. Use them to compare ordinary playable screenshots, not to create a staged-only screenshot mode.

| Element | Target reading | 3D implementation criterion |
|---|---|---|
| Camera | Low oblique spectator view from behind the near team | Perspective projection; moderate downward pitch, approximately 12–18 degrees as a starting range. Preserve a visible sky/sea horizon. Avoid an overhead/isometric camera. |
| Horizon | Approximately 30–35% down the frame on the left | Keep a strip of blue sea beneath pale horizon sky; town rises above this horizon on the right. |
| Net top | Approximately 44–46% down the frame | Net should cut through mid-scene, with ball/attacking hands above it. The tape must not function as a screen-space overlay. |
| Net span | Roughly 55–60% of frame width | Enough projected width for three readable lanes and separate blocker/attacker silhouettes. Posts remain inside the side frame margins. |
| Play surface | Occupies lower half and expands toward the viewer | Actual planar court with receding line geometry; near boundary may approach the frame edge, but every reachable athlete and ball-contact location must remain visible during normal play. |
| Near players | Strong foreground presence, roughly 25–35% frame height when standing in the near half | Player scale must come from depth, not per-character screen scaling. Allow a jump pose to exceed standing silhouette height. The reference's hero pose is unusually large; readable ordinary play takes precedence over copying that single pose literally. |
| Far defenders | Roughly 12–16% frame height; readable crouches and lateral gaps | Do not shrink far players into tiny tokens. Preserve numbers/kit identity and arm/leg silhouette even when facial detail is less visible. |
| Three near lanes | Near left attack, central/back setter, right cover | Distinct world positions; avoid the ball-facing actor hiding a teammate directly behind them. Do not stack all three at equal depth. |
| Far formation | One front blocker and two spaced back defenders | The net should hide only physically occluded parts. Raised hands must visibly clear the tape; two back defenders remain readable beneath/around the front player. |
| Environment frame | Trees at both upper corners, sea left, town and cafe right/upper center | Large foreground canopies belong outside the player-contact volume. Their branches frame the image without masking the ball apex or net antennae. |
| HUD | Cream cards in corners, small top score, compact lower controls/portraits | Keep it crisp and subordinate to the 3D scene; protect near player feet, landing rings, and the full serve toss. |

## Camera and dimensions: usable starting configuration

Use a clear convention: X is lateral, Y is height, Z is court depth; near team has positive Z. Existing gameplay coordinates can map `(x, y)` to world `(x, 0, y)` without changing match rules. Start with the current 9×16 logical court, net at Z=0, then decide whether the rendered world court should be proportionally wider for three-player readability. If a scale factor is used, apply it to players, ball, tactical indicators, collision/reach visuals, and court lines consistently.

An analytically reasonable first camera for a 9×16 court is `position=(0, 5.5, 17)`, looking at `(0, 1.2, -1)`, with a vertical FOV around 45 degrees. This places net-top height 2.43 around 43% of the frame and the near baseline around 89% at a 940-pixel-high image. These are approximate pinhole projections, not runtime-verified Godot settings. This configuration preserves baseline visibility but produces a narrower net span than the reference; a physical 11–12 m court width (or a uniformly applied lateral world scale) can recover more of its framing without clipping the near baseline.

A closer camera around Z=13 with FOV near 38 degrees produces more dramatic net/foreground scale but clips near-baseline service and defensive chases. Reject that as the default if normal contacts fall below the frame. Do not solve this by shrinking only the near players. Check the actual six-player default formation, full serve position, all attack lanes, deepest reachable receive, and maximum ball apex before finalizing camera placement. A very gentle camera target adjustment may accommodate an apex, but it must not move unpredictably during timing windows.

Use one coherent human scale, approximately 1.75–1.95 m standing, with distinct height/shoulder/leg proportions. A useful initial anatomy is about 7–7.5 head lengths tall, head height 0.24–0.27 m, shoulder width 0.40–0.48 m, hip width 0.29–0.36 m, rather than a sphere-head/capsule-body toy. The net's top can begin at 2.35–2.43 m and its mesh band should be about 1 m deep, leaving ground clearance; body, ball, hand-reach, and tape must use those same units. Ball diameter around 0.21–0.23 m is a physical starting point; a modest consistent visibility exaggeration is acceptable if hand contact remains aligned.

## Environment construction order

1. **Court and net with six untextured articulated athletes.** Establish the camera and foreground/background scale first. In normal play, the ball must occupy the same 3D hand-contact point used by the animation and projected indicator.
2. **Actual light and ground contact.** Warm upper-left sun, cooler sky fill, real cast shadows from bodies/net/trees, and contact darkening where shoes meet clay. The scene must read as sunlight before adding a painterly post effect.
3. **Large scene masses.** Left cliff/sea descent, right retaining wall and cafe terrace, central ascending stairs, staggered buildings climbing behind them, two framing trees. These depth layers matter more than extra windows.
4. **Architecture as volumes.** Recessed window planes, balcony slabs/rails, projecting awnings and eaves, variable roof heights; keep the target's creamy stucco and dark blue-green cafe awning. Preserve sightlines through to the ascending stairs.
5. **Planting as clustered 3D form.** Dark inner canopy, brighter outer leaves, gaps exposing sky, uneven lobes and asymmetric branches. Place low shrubs beside walls/rails rather than uniformly scattering identical green objects.
6. **Materials and restrained atmosphere.** Coarse clay variation, stucco mottling, bark direction, roof/stone detail, small wave streaks and rocky foam, distant desaturation. Avoid uniform screen noise as the main source of painterliness.

## Cozy Sora techniques worth copying locally

All paths below are within `games/cozysora`. Copy the smallest necessary helper/resources into Spike Season so it remains independently runnable; retarget `res://` paths and avoid importing the whole Cozy Sora scene/application.

| Source | Useful technique | Adaptation for Spike Season |
|---|---|---|
| `shared/atmosphere.gd` and `maps/seabreeze_village/atmosphere.tres` | Warm sun energy 1.32, cool ambient 0.48, small cool fill 0.16, filmic tone mapping, SSAO, depth fog, real filtered directional shadows | Build the court's lighting from this foundation. Restrict fog to the town/distant coastline; do not wash out nearby players. Its warm sun position/rotation is a starting point, not a fixed camera-independent choice. |
| `project.godot` | Forward Plus renderer, MSAA setting 2, 4096 directional-shadow texture, filtered shadows | Preserve the rendering features actually used by the atmosphere. The old 2D project's Compatibility configuration should not silently disable the intended 3D lighting presentation. Verify the selected renderer on the target machine. |
| `maps/seabreeze_village/plant_meshes.gd` | Lobed canopy volumes, clusters of rotated leaf cards, outward-biased smooth normals, tint variation, tapered branching trunk geometry | Strong fit for the two hero trees and terrace planting. Use a few varied mesh recipes, not dozens of separate bespoke trees. Cut alpha-scissored leaves can still cast real shadows. |
| `maps/seabreeze_village/textures.gd` and `shared/leaf_painter.gd` | Deterministic locally generated leaf silhouettes, bark texture, flowers | Reuse image generation recipes, preserving the no-download constraint. Multiple seeds/sizes prevent repeated crown stamps. |
| `shaders/foliage.gdshader` | Alpha scissor threshold 0.45, banded directional light response, outward normals, subtle backlight, wind weighted by vertex alpha | Remove `cat_position`-specific player push and the near-camera discard behavior. Volleyball players should not cause court-framing canopy geometry to vanish or bend through the ball path. Reduce sway for gameplay readability. |
| `shared/mesh_batches.gd` | MultiMesh spatial cells, grouped transforms/materials, optional shadow-only near batches, static mesh merging | Batch repeated leaf clusters/railings/windows; keep animated characters, moving net/ball, and interaction markers separate. A single court scene needs far fewer cells than Cozy Sora's open world. |
| `shaders/sky.gdshader` | Noise-derived cumulus masses with directional cool/warm shading and blue horizon gradient | Better starting point than stacked cloud spheres. Keep cloud detail behind the ball subdued; match sun direction between sky and world light. |
| `shaders/ocean.gdshader` and `shared/surface_noise.gdshaderinc` | World-space anisotropic wave streaks, sparse glints, distance fading, animated noise | Use on a real ocean plane below the cliff. Retain rocks/foam geometry near shore to establish height separation. |
| `maps/seabreeze_village/finishes.gd`, `settlements.gd` | Generated stucco/stone/wood finishes, roof construction, window recesses, balconies, awnings, coastal props | Copy facade and material recipes selectively. Real depth and shadows should replace the current flat drawn facade stack. |
| `shaders/paint.gdshader` | Four-region variance filter, restrained saturation/tonal mapping and vignette | Apply only after the 3D scene already has convincing form. It samples 64 nearby texels per pixel, so start with radius 1–2 and assess runtime performance. Composite world below a sharp HUD; do not blur faces/ball/timing UI into illegibility. |

## Manual review gates for the rebuild

These are runtime inspection criteria, not automated tests.

- **Genuine 3D:** moving the camera temporarily in the editor reveals complete bodies, court, net, buildings and trees with consistent parallax; silhouettes are not billboard replacements. Restore the intended gameplay camera afterward.
- **Normal-play composition:** obtain one ordinary serve, near-side set/spike, rival attack, and deep receive frame. All six players, the relevant landing region, and the ball/contact hands remain legible. No screenshot-only actors or camera placement.
- **Depth and scale:** near athletes are meaningfully larger than far defenders; world-height net remains above grounded heads and below fully extended jumping hands; the net's bottom does not reach the court floor.
- **Physical contact:** hand/forearm and ball meet in world space; a failed contact passes beyond bounded reach; foot plants and landing shadows stay on the same ground plane. Avoid screen-space post-correction that hides 3D misalignment.
- **Athletic posing:** receive drops the hips and joins the platform; set extends from a compressed stance; spike shows a planted approach, torso/hip opposition, leading reach and trailing leg; block has two hands over the tape. Recovery returns smoothly to readiness.
- **Light/materials:** real directional shadows visibly change with body/leaf pose and lie consistently across clay and lines. Lit walls, cool recesses, shaded canopy interiors, and distant coast remain distinct without excessive bloom or fog.
- **Reference comparison:** compare same-size screenshots beside the approved image. Judge camera angle, foreground figure size, six-player lane spacing, tree framing, sea/town split, and depth layering before judging small decorative details.

Current verdict: the normal 2D baseline does not meet the new genuine-3D goal. The directions above establish a concrete implementation/review target; no 3D runtime approval is implied until the rebuilt scene is inspected in ordinary play.
