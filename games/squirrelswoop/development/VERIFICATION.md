# Runtime verification — 5 September 2026

Godot **4.7.2**, macOS, Apple M3 Max, Compatibility renderer. Verification consisted of live rendered play using discrete, manually chosen controls through the opt-in loopback console, injected Godot key events, viewport captures, and independent code/visual review. **No automated tests were created.** These observations demonstrate behavior, not that every player will find the game fun.

## Demonstrated flight and flow

| Check | Observation |
| --- | --- |
| Starting directions | Summit view shows open meadow left, a continuous stream center, and dense woods right. Launch begins from a rocky perch. |
| Beginner descent | Independent reviewer banked left then released controls; survived a continuous **3,044.70 m** descent on seed **752041**. At the end: 63 active sections, 401 generated, no pending backlog, 57 FPS. |
| Free crossings | Reviewer flew meadow → stream → woods → stream → meadow without teleportation, gates, or route selection. Woods reached x41.75/d110; return crossed stream at x4.99/d189 and meadow at x−61.46/d286. Final-build root replay also crossed meadow → woods → stream, with a close-pass bonus on return. |
| Pitch and momentum | Final key-input replay: holding **S** changed speed 20.73 → 17.34 m/s and clearance 5.55 → 8.47 m. Holding Space for about 0.6 seconds changed speed to 22.28 m/s and clearance to 6.51 m. Releasing recovered to 7.69 m clearance at 21.99 m/s. |
| No unlimited lift | Review found and root fixed an indefinite pull-up exploit. Revised model held full pull for 28.3 seconds: speed settled at 16.50 m/s; clearance settled back to 8.20 m rather than climbing above the trees. |
| Fast collision | Independent reviewer dove into terrain at **32.249 m/s (116 km/h)**. Collision ended the run and displayed the ground-impact result; no tunneling was observed. |
| Same seed | Two retries on seed **752041** with the same neutral controls hit the same tree at **84.223831 m**, with identical position, speed, and score despite different render frame rates. A left-bank line survived, showing that the hazard was avoidable. |
| Multiple seeds | Both **482193** and **752041** were played. Their terrain/obstacles and neutral collision points differed. |
| New wooded shelves | After strengthening wooded shelves to 13–21 m and enlarging boulders, root placed the review scene at d2280/x69.65 and then flew it normally. Neutral flight traversed the drop to d2363 at 8.63 m clearance. A short dive reached 25.25 m/s; release continued across the apron to d2427 at 6.01 m clearance. This is a **local terrain review**, not a claimed 2.4 km descent from the summit. |
| Menu keyboard navigation | Tab/Enter opened settings, arrow adjusted sound to 0.75, Space toggled assistance off and reduced motion on, and Done returned to summit. Enter activated the focused launch button. Settings were then restored. |
| Pause | Escape key event opened the visible pause menu. Distance, position, and flight time remained frozen while paused; resume continued the run. |
| Saves | Reviewer returned to summit before crashing, changed settings, quit, and relaunched a different seed. Distance 930.25604, score 1242.989, volume, assistance, reduced motion, and inverted pitch survived. This explicitly rechecked the earlier record-overwrite bug. |
| Fresh launch | Reviewer copied the project without `.godot` and confirmed direct launch after dependencies were changed to explicit preloads. Editor import and actual rendered startup also succeeded. |

The independent long-run evidence predates the last foliage, camera, and rock-collider refinements. Final-build short runs and the local shelf flight rechecked the changed areas. Final forest observations ranged approximately **43–60 FPS** while another unrelated Godot project was also running on this machine; this is not a cross-device benchmark.

## Independent review and changes made

Three agents independently examined different areas, with follow-up reviews after substantive changes:

- **Terrain, variety, and fairness:** replaced fixed repeated corridors/clearing strips with seeded formations, varying passage positions/widths, long achievable diagonal connections, recovery stretches, and capped progression. Raised canopy apertures and matched solid branch collisions to their meshes. Larger rocks preserve corridor setbacks; final ellipsoid collisions include rock rotation. Terrain and stream seams use identical world-coordinate functions.
- **Flight, accessibility, and replay:** fixed records being overwritten after returning to summit, controller confirm inadvertently diving, warnings arriving too late, and indefinite pull-up gaining altitude relative to terrain. Reduced excess-speed drag so useful dive momentum lasts longer. The reviewer demonstrated beginner cruising, crossings, pull-up, diving, recovery, high-speed impact, reproducibility, saving, and sustained generation.
- **Visual fidelity:** replaced polygon canopy wedges with locally painted fine pine needles on drooping 3D cards; added bark, mineral/moss, and duff variation; rebuilt the flattened furry tail and corrected membrane normals/camber. Adapted Cozy Sora's local sky and brush-filter shaders. The reviewer found no blocking readability issue in the revised scene. An isolated identical-view comparison traced dotted card-edge lines to Compatibility-renderer MSAA; MSAA was disabled, retaining the brush filter.

The ground corridors have geometric obstacle-clearance margins and a connection steering ratio below the dive limit. The runtime descents support traversability. This is **not** an exhaustive proof for every seed, altitude, speed, or player input combination.

## Visual evidence

All images were captured from Godot's rendered viewport. `visual-target.png` is reference only and is excluded from Godot's asset scan.

- `evidence/01-summit.png`: visible introduction and three directions.
- `evidence/02-meadow.png`: open meadow descent.
- `evidence/03-forest.png`: actual woodland entry.
- `evidence/04-stream.png`: actual return through the stream route.
- `evidence/05-dive-recovery.png`: actual recovered glide.
- `evidence/06-pause.png`: visible paused state.
- `evidence/07-three-kilometres.png`: independent 3 km run, earlier visual build.
- `evidence/08-high-speed-impact-earlier-build.png`: independent high-speed impact/results.
- `evidence/09-settings.png`: visible settings screen, reached using keyboard navigation.
- `evidence/10-shelf-review.png`: local shelf review described above.
- `evidence/11-results.png`: final-build collision and complete retry/results menu.

The final scenery is a coherent **stylized procedural interpretation** of the target. The reference has richer rocky ravine detail, more organic massive trunks, and more natural filtered light. Exact visual fidelity is not claimed. Physical gamepad operation, tactile keyboard feel for a human player, other GPUs/operating systems, and arbitrarily long runs beyond the recorded sustained descent remain unverified.
