# Overrush

Overrush is a minimalist procedural freeriding game. The playable experience is a focused sandboarding run: choose any direction from a high central summit, read the terrain, carve for speed, jump, land cleanly, and use one directional air boost per airtime. Its unbounded landscape blends dunes, grassland forests, and sparse weathered ruins without adding combat or progression systems.

## Governing quality direction

SNØ is the benchmark for the finished experience's graphical fidelity, collision clarity, obstacle tension, and convincing sensation of descending a mountain. Overrush must reach equivalent commercial quality with its own terrain technology, art, rider, biomes, ruins, presentation, and identity; reference parity is not permission to copy another game's assets or distinctive content.

Work stays inside the freeriding core: steep sustained multidirectional descent, carving, jumps and clean landings, the single air boost, readable high-speed terrain, dense but fair tree and rock line choices, consequential direct impacts, cohesive audiovisual feedback, streaming, accessibility, and playtest polish. Prefer replacing unfinished presentation and tuning existing systems over adding features. Combat, builds, progression, quests, collectibles, crafting, dialogue, and other unrelated breadth remain out of scope.

The goal remains incomplete until external playtests confirm that the original graphics no longer read as placeholders, the mountain scale and downhill sensation are convincing, tree and rock frequency creates frequent fair line-reading decisions, direct high-speed impacts end the run predictably, and traversal alone sustains repeated runs.

## Current playable foundation

- `freeride.tscn` is the project entry scene. It contains no enemies, weapons, builds, health, pickups, or survivor progression.
- Each run creates a deterministic, unbounded radial mountainscape with a compact central summit, broad seeded folds, large valleys, ridges, and smaller dunes. A stronger sustained base grade makes the opening read and ride as a mountainside rather than level traversal. Mountain-scale folds now emerge gently from 180 m across a broad 780 m transition while local dunes and kickers retain a protected 260 m threshold, so the opening gains visible valleys without abrupt blockers. The terrain gate requires at least 80 m of descent within 250 m plus 5,000 m over 12 km in every sampled heading and mountain-scale lateral relief.
- A bounded 5 × 5 neighborhood of seamless 384 m terrain chunks follows the rider. Each chunk now uses a 65 × 65 visual/collision grid for smoother steep slopes; new outer chunks are prepared incrementally while distant chunks retire.
- Horizontal and vertical floating-origin rebasing keeps the rider, camera, and resident terrain close to local zero without changing logical position, distance, terrain sampling, or shader continuity.
- A bounded infinite-cell grammar layers smooth bowls, readable ridges, broad kickers, split-line dune pairs, and open breathing space without defining a route corridor.
- A separate deterministic landscape layout blends broad dune and grass regions, guarantees that every tested outward heading reaches both, preserves open glades and the summit drop-in, and places trees without per-chunk randomness or seam discontinuities. Broad highland biome lobes now guarantee that every audited seed offers several open dune and wooded choices within the first 1.2 km instead of occasionally generating a tree-free opening mountain.
- Forests use batched tapered trunks and original six-tier conifer crowns built from staggered branch fans, a shaded inner crown, jagged edge heights, and subtle per-tree lean. Deterministic cool-to-warm foliage, trunk value variation, and restrained canopy emission separate adjacent trees while keeping direct light and partial shadows responsible for their form. The fuller ground-to-tip silhouette stays inside one bounded shared mesh, while one consolidated two-sided concave collision mesh replaces hundreds of per-tree scene nodes and supports reliable rider and camera queries from either direction. Deterministic centers, fatal direct impacts, glades, and tested trunk spacing remain unchanged.
- Clustered rock fields complement the authored rock gates. Their tuned opening density creates regular decisions in both forest and dune approaches while retaining deliberately open headings. Rock placement has sole ownership where forest and field candidates overlap: nearby trees yield clearance instead of both hazards disappearing. Original five-ring weathered boulders use rounded asymmetric profiles, varied transforms, warm terrain-cohesive stone shading, and batched rendering rather than pointed primitive shards or uniform obstacle carpets; efficient forgiving sphere collisions stay slightly inside the visible rocks so near misses remain fair at speed.
- Sparse original arch-and-terrace ruins sit safely inside non-neighboring chunks. Each landmark preserves five simple collision volumes and a wide passage while 34 bevel-edged masonry pieces form subtly irregular block courses, column bases and caps, inset relief panels, broken pylons, and a stepped central crest. Warmer shadow-filled stone keeps the silhouette readable against both sand and grass. They remain optional line-reading landmarks rather than routes, objectives, or combat spaces.
- Sparse procedural sandstone gates create visible passage decisions outside the summit. Their dedicated obstacle colliders never qualify as rideable landings or refresh the air boost.
- All tested outward headings descend and remain available to the player; there is no route corridor or prescribed forward direction.
- The sandboard controller gains speed from the component of the slope aligned with the board instead of receiving a direction-agnostic downhill shove. Traversing holds a line, pointing downhill builds speed, uphill lines decelerate, and committed high-speed carves pay a bounded edge-load cost while preserving momentum. The speed-scaled carve envelope avoids direction snapping and a fixed powered target speed. A 1.6 m terrain-follow snap keeps ordinary high-speed carving planted across readable slope changes without suppressing deliberate jumps or larger natural launches; the sustained no-jump gate remains at least 93% grounded while requiring occasional terrain airtime.
- Buffered/coyote jumps launch along the contacted terrain normal while preserving approach momentum. Rideable-terrain landings resolve predictably from impact and alignment as clean, solid, or rough, with bounded momentum retention.
- The directional air boost adds to existing momentum. It has exactly one charge in the air and only a valid landing on tagged rideable terrain refreshes it.
- Direct tree, rock, or ruin impacts with at least 10 m/s of closing speed end the run immediately. Tree and rock collision radii stay inside their visible silhouettes, while low-speed bumps and fast grazing contact remain recoverable; a 0.32-second consequence beat shows contact debris and a frozen sprawled rider/board pose while a dedicated synthesized impact cue lands, then the run-ended overlay identifies the obstacle and impact speed. `Drop Again` clears every crash state and performs a clean summit reset. The real controller is regression-tested against 88 m/s tree and rock strikes at 30 physics ticks per second plus a 1.55 m tree skim, covering both swept-impact reliability and fair near misses.
- Board pitch and bank, biome-aware carve-directed surface clumps, a readable bounded terrain-conforming groove, contact bursts, continuous speed wind, crossfaded sand/grass board contact, synthesized jump/landing cues, and a restrained HUD communicate speed, chosen lines, contacted terrain, landing quality, and boost state. The short-lived GPU wake fans outward under edge pressure and fades cleanly; the narrow low-opacity track breaks across airtime, follows floating-origin rebases, fades behind the rider, and clears at the summit rather than resembling a painted path, bridging gaps, or growing forever. Contact audio falls silent in the air while wind carries momentum; pause and crashes silence all motion loops.
- A close, elevated third-person camera looks down into the chosen mountain line and widens continuously with speed. Its follow response increases with rider velocity so high-speed lag cannot shrink the rider into the horizon, while low-speed orbit remains smooth. Tree, rock, and ruin sightlines contract immediately in front of the obstacle and release smoothly after orbiting clear, while reduced-motion mode holds a steady FOV. A dedicated 2.9 m beveled sandboard mesh has a shaped outline, independently upturned nose and tail, inset deck pad, edge rails, and bindings instead of the former scaled cylinder. The articulated rider separates a readable teal jacket, charcoal pants, and mid-tone helmet, with a rounded shoulder yoke, hood, visor, waist, knee protection, gloves, and boots instead of a single dark mannequin silhouette; speed crouch, carve lean and counterbalance, airborne tuck, boost commitment, and landing compression remain intact.
- A seam-matched graded high-desert sky, restrained fog influence, lower warm sunlight, cool ambient fill, softened partial obstacle shadows, smoother mountain geometry, a restrained alpine-and-sand palette, original high-detail albedos at believable ground scale, lit stone landmarks, directional slope shading, SSAO, and a short-lived carve-directed surface wake keep slopes, distant ridges, and motion readable without crushing rideable ground into black bands or changing the Forward+ renderer configuration. Restrained texture mixing preserves material detail without muddying large terrain forms, while rotated secondary world-space sampling remains continuous across streamed chunk seams.
- Mouse/right-stick orbit controls retain the existing free camera behavior.
- Reduced camera motion, shared mouse/gamepad look sensitivity, and master volume are available before drop-in and while paused. Both control surfaces remain synchronized and persist through `user://overrush_settings.cfg`.

The previous movement-survivor scene and all of its combat, enemy, weapon, build, progression, boundary, and alternate-world implementation have been removed. The project now contains one entry scene and only the runtime systems used by the focused freeride game.

This is still a foundation, not the completed game or SNØ-quality parity proof. More bespoke production assets, repeated hands-on movement tuning, more detailed rider animation, effects refinement, accessibility, long-session streaming/performance soaks, and external playtest comparison against SNØ remain required.

## Controls

- `W` / `A` / `S` / `D` or left stick: carve relative to the camera
- Mouse or right stick: orbit the camera independently
- `Space` or gamepad `A`: jump
- `Shift` / `Alt` or either shoulder button: use the single directional air boost while airborne
- `Escape` or Start: pause

## Architecture

- `procedural_desert.gd` owns seeded radial terrain generation, seamless visual/collision chunks, batched forest and ruin streaming, and floating-origin rebasing.
- `desert_feature_grammar.gd` owns the deterministic, cache-bounded macro-feature distribution and its smooth analytic landforms.
- `landscape_layout.gd` owns deterministic biome blending, glades, dense tree cells, clustered rock cells, and sparse separated ruin sites.
- `sandboard_motion.gd` owns the testable board-aligned slope drive, speed-scaled carve and edge-load envelope, clean/solid/rough landing assessment, and closing-speed crash rule.
- `jump_assist_state.gd` owns the single-consume 130 ms input buffer and 100 ms coyote window independently of frame rate.
- `sandboarder.gd` integrates slope-driven movement, buffered/coyote jumps, the bounded player-owned sandboard mesh, surface-aligned and biome-aware contact feedback, the bounded carve-track ribbon, and boost application.
- `air_boost_state.gd` owns the small testable one-charge, rideable-ground-only refresh contract.
- `follow_camera.gd` owns independent mouse/right-stick orbit and speed feedback.
- `input_bindings.gd` owns only the 11 traversal, camera, jump, boost, and pause actions used by the final game.
- `audio_director.gd` owns one ambient layer, three continuously mixed traversal loops, and six core cues for jumping, boosting, landing quality, and fatal obstacle impacts.
- `desert.gdshader` owns seamless world-space sand/grass blending, directional slope depth, and fine wind-ridge readability.
- `freeride_main.gd` owns the minimal run lifecycle, onboarding, crash/pause flow, and HUD.

## Focused validation

Run the boost-state contract, combat-free runtime integration, radial terrain sweep, input mapping, and project boot checks with:

```sh
godot --headless --path games/overrush --script res://tests/test_air_boost_state.gd
godot --headless --path games/overrush --script res://tests/test_audio_synthesis.gd
godot --headless --path games/overrush --script res://tests/test_sandboard_motion.gd
godot --headless --path games/overrush --script res://tests/test_jump_assist_state.gd
godot --headless --path games/overrush --script res://tests/test_desert_feature_grammar.gd
godot --headless --path games/overrush --script res://tests/test_landscape_layout.gd
godot --headless --path games/overrush --script res://tests/validate_freeride_runtime.gd
godot --headless --path games/overrush --script res://tests/validate_freeride_presentation.gd
godot --headless --path games/overrush --script res://tests/validate_camera_obstacles.gd
godot --headless --path games/overrush --script res://tests/validate_freeride_pause_restart.gd
godot --headless --fixed-fps 120 --path games/overrush --script res://tests/validate_fatal_obstacles.gd
godot --headless --path games/overrush --script res://tests/validate_project_scope.gd
godot --headless --path games/overrush --script res://tests/validate_desert_terrain.gd
godot --headless --path games/overrush --script res://tests/validate_desert_streaming.gd
godot --headless --path games/overrush --script res://tests/validate_landscape_streaming.gd
godot --headless --path games/overrush --script res://tests/validate_long_session_streaming.gd
godot --headless --fixed-fps 300 --path games/overrush --script res://tests/validate_sandboard_motion.gd
godot --headless --fixed-fps 300 --path games/overrush --script res://tests/validate_sandboard_jump_landing.gd
godot --headless --path games/overrush --script res://tests/test_input_bindings.gd
godot --headless --path games/overrush --quit-after 12
```

The scope gate locks the project to one entry scene, eleven justified runtime scripts, one shader, eleven inputs, three traversal loops, and six core event cues so legacy survivor complexity cannot quietly return. The feature gate checks deterministic seed variation, balanced feature-family distribution, smooth cell boundaries, bounded cache residency, meaningful relief, and a maximum authored-feature grade. The landscape-layout gate verifies that every sampled heading crosses clear dune and forest regions, biome changes remain gradual, forests and rock fields are consequential but clustered, the summit and glades remain open, ruins remain sparse, and eight representative seeds each offer bounded opening tree/rock pressure plus both wooded and open line choices. A corridor audit now measures occupied 100 m bands across 30 m-wide downhill lines, requiring regular decisions while capping local pressure and preserving several intentionally open headings. The presentation gate rejects primitive player, tree, rock, and ruin silhouettes; requires a shaped upturned board, complete rider equipment, a dense but vertex-bounded conifer crown with jagged asymmetric bough edges, and a 34-piece arch-and-crest landmark; and checks finer mountain sampling, believable ground-detail scale, biome-aware carve-directed spray, the bounded subtle carve track, graded daylight separation, sightline-safe fog, downhill camera composition, speed-responsive follow, rider readability, continuous speed FOV, and the reduced-motion override. The camera-obstacle gate casts through real streamed tree and rock shapes, requires contraction before either collider, and verifies gradual full-distance recovery after the sightline clears. The terrain sweep samples 16 radial lines over 12 km, requires an immediate all-direction summit drop followed by at least 5 km of net descent, mountain-scale cross-slope relief, every terrain feature family, and multiple rock passages while rejecting non-finite terrain or abrupt local rises. The streaming gates compare adjacent mesh borders, normals, and biome weights; verify collision continuity plus obstacle identity; enforce grass-only trees, open passages, and non-rideable landmarks; simulate 22 km of focused rebasing plus a 52.8 km multidirectional stress route; and check logical precision, transition cost, and bounded chunk residency. The motion gates prove that board direction governs slope drive, hard carves cost more speed than shallow ones, and sustained turning preserves useful momentum; they also require a predominantly grounded no-jump descent with no more than two bounded natural launches and prove the carve track stays bounded across sustained travel and breaks rather than drawing through airborne gaps. The fatal-obstacle gate drives the real controller into both a tree and rock at 88 m/s and 30 Hz, proves direct hits end the run while a close skim remains fair, verifies decisive impact feedback, and checks a clean summit restart. These automated gates establish a stronger foundation; they do not substitute for a real-time long-session soak or hands-on and external playtests.
