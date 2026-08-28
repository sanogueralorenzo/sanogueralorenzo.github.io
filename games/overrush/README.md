# Overrush

Overrush is a minimalist procedural freeriding game. The playable experience is a focused sandboarding run: choose any direction from a high central summit, read the terrain, carve for speed, jump, land cleanly, and use one directional air boost per airtime. Its unbounded landscape blends dunes, grassland forests, and sparse weathered ruins without adding combat or progression systems.

## Current playable foundation

- `freeride.tscn` is the project entry scene. It contains no enemies, weapons, builds, health, pickups, or survivor progression.
- Each run creates a deterministic, unbounded radial mountainscape with a softened central summit, broad seeded folds, large valleys, ridges, and smaller dunes. The terrain gate now requires at least 3,900 m of descent over 12 km in every sampled heading plus mountain-scale lateral relief.
- A bounded 5 × 5 neighborhood of seamless 384 m terrain chunks follows the rider. Each chunk now uses a 65 × 65 visual/collision grid for smoother steep slopes; new outer chunks are prepared incrementally while distant chunks retire.
- Horizontal and vertical floating-origin rebasing keeps the rider, camera, and resident terrain close to local zero without changing logical position, distance, terrain sampling, or shader continuity.
- A bounded infinite-cell grammar layers smooth bowls, readable ridges, broad kickers, split-line dune pairs, and open breathing space without defining a route corridor.
- A separate deterministic landscape layout blends broad dune and grass regions, guarantees that every tested outward heading reaches both, preserves open glades and the summit drop-in, and places trees without per-chunk randomness or seam discontinuities.
- Forests use batched trunks and three-part organic crowns with one explicit obstacle body per chunk. Tree placement is roughly four times denser than the initial forest pass while deterministic glades and tested trunk spacing preserve readable lines.
- Clustered rock fields complement the authored rock gates. Their varied silhouettes and batched rendering create frequent line decisions without filling every chunk uniformly.
- Sparse original arch-and-terrace ruins sit safely inside non-neighboring chunks. Their wide passages act as optional line-reading landmarks rather than routes, objectives, or combat spaces.
- Sparse procedural sandstone gates create visible passage decisions outside the summit. Their dedicated obstacle colliders never qualify as rideable landings or refresh the air boost.
- All tested outward headings descend and remain available to the player; there is no route corridor or prescribed forward direction.
- The sandboard controller gains speed from terrain slope, uses a speed-scaled carve envelope instead of direction snapping, and avoids a fixed powered target speed.
- Buffered/coyote jumps launch along the contacted terrain normal while preserving approach momentum. Rideable-terrain landings resolve predictably from impact and alignment as clean, solid, or rough, with bounded momentum retention.
- The directional air boost adds to existing momentum. It has exactly one charge in the air and only a valid landing on tagged rideable terrain refreshes it.
- Direct tree, rock, or ruin impacts with at least 10 m/s of closing speed end the run immediately. Low-speed bumps and fast grazing contact remain recoverable; the run-ended overlay identifies the obstacle and impact speed, and `Drop Again` performs a clean summit reset.
- Board pitch and bank, biome-aware surface spray, contact bursts, synthesized jump/landing cues, and a restrained HUD communicate speed, contacted terrain, landing quality, and boost state.
- A close third-person camera now widens continuously with speed, while reduced-motion mode holds a steady FOV. The rounded board and articulated high-contrast rider replace the earlier box-and-capsule silhouette.
- A brighter cool-sky/warm-horizon grade, readable shadow fill, smoother mountain geometry, terrain mottle, lit stone landmarks, directional slope shading, SSAO, and rounded spray grains keep slopes and motion readable without changing the Forward+ renderer configuration.
- Mouse/right-stick orbit controls retain the existing free camera behavior.

The previous movement-survivor scene and all of its combat, enemy, weapon, build, progression, boundary, and alternate-world implementation have been removed. The project now contains one entry scene and only the runtime systems used by the focused freeride game.

This is still a foundation, not the completed game or visual-parity proof. Bespoke production assets, repeated hands-on movement tuning, more detailed rider animation, effects refinement, accessibility, long-session streaming/performance soaks, and external playtest comparison against SNØ remain required.

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
- `sandboard_motion.gd` owns the testable speed-scaled carve envelope, clean/solid/rough landing assessment, and closing-speed crash rule.
- `jump_assist_state.gd` owns the single-consume 130 ms input buffer and 100 ms coyote window independently of frame rate.
- `sandboarder.gd` integrates slope-driven movement, buffered/coyote jumps, surface-aligned and biome-aware contact feedback, and boost application.
- `air_boost_state.gd` owns the small testable one-charge, rideable-ground-only refresh contract.
- `follow_camera.gd` owns independent mouse/right-stick orbit and speed feedback.
- `input_bindings.gd` owns only the 11 traversal, camera, jump, boost, and pause actions used by the final game.
- `audio_director.gd` owns one ambient layer and the five movement cues for jumping, boosting, and landing quality.
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
godot --headless --path games/overrush --script res://tests/validate_freeride_pause_restart.gd
godot --headless --fixed-fps 120 --path games/overrush --script res://tests/validate_fatal_obstacles.gd
godot --headless --path games/overrush --script res://tests/validate_project_scope.gd
godot --headless --path games/overrush --script res://tests/validate_desert_terrain.gd
godot --headless --path games/overrush --script res://tests/validate_desert_streaming.gd
godot --headless --path games/overrush --script res://tests/validate_landscape_streaming.gd
godot --headless --fixed-fps 300 --path games/overrush --script res://tests/validate_sandboard_motion.gd
godot --headless --fixed-fps 300 --path games/overrush --script res://tests/validate_sandboard_jump_landing.gd
godot --headless --path games/overrush --script res://tests/test_input_bindings.gd
godot --headless --path games/overrush --quit-after 12
```

The scope gate locks the project to one entry scene, eleven justified runtime scripts, one shader, eleven inputs, and five movement cues so legacy survivor complexity cannot quietly return. The feature gate checks deterministic seed variation, balanced feature-family distribution, smooth cell boundaries, bounded cache residency, meaningful relief, and a maximum authored-feature grade. The landscape-layout gate verifies that every sampled heading crosses clear dune and forest regions, biome changes remain gradual, forests and rock fields are consequential but clustered, the summit and glades remain open, and ruins remain sparse. The presentation gate checks layered tree crowns, finer mountain sampling, biome-aware spray, atmospheric separation, sightline-safe fog, rider readability, close framing, continuous speed FOV, and the reduced-motion override. The terrain sweep samples 16 radial lines over 12 km and requires steep sustained descent, mountain-scale cross-slope relief, every terrain feature family, and multiple rock passages while rejecting non-finite terrain or abrupt local rises. The streaming gates compare adjacent mesh borders, normals, and biome weights; verify collision continuity plus obstacle identity; enforce grass-only trees, open passages, and non-rideable landmarks; simulate 22 km of repeated rebased travel; and check bounded chunk residency. The fatal-obstacle gate drives the real controller into both a tree and rock, proves each impact ends the run, and verifies a clean summit restart. These automated gates establish a foundation; they do not substitute for long-session performance soaks or hands-on and external playtests.
