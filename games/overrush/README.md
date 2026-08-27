# Overrush: Dune Drifter

Overrush is being rebuilt as a minimalist desert freeriding game. The shipped scene is now a combat-free sandboarding run: choose any direction from a high central summit, read the terrain, carve for speed, jump, land cleanly, and use one directional air boost per airtime.

## Current playable foundation

- `freeride.tscn` is the project entry scene. It contains no enemies, weapons, builds, health, pickups, or survivor progression.
- Each run creates a deterministic, unbounded radial desert with a softened central summit, broad landforms, folded ridges, and smaller dunes.
- A bounded 5 × 5 neighborhood of seamless 384 m terrain chunks follows the rider. New outer chunks are prepared incrementally while distant chunks retire.
- Horizontal and vertical floating-origin rebasing keeps the rider, camera, and resident terrain close to local zero without changing logical position, distance, terrain sampling, or shader continuity.
- A bounded infinite-cell grammar layers smooth bowls, readable ridges, broad kickers, split-line dune pairs, and open breathing space without defining a route corridor.
- Sparse procedural sandstone gates create visible passage decisions outside the summit. Their dedicated rock colliders never qualify as sand landings or refresh the air boost.
- All tested outward headings descend and remain available to the player; there is no route corridor or prescribed forward direction.
- The sandboard controller gains speed from terrain slope, preserves momentum while carving, supports camera-relative steering and jumping, and avoids a fixed powered target speed.
- The directional air boost adds to existing momentum. It has exactly one charge in the air and only a valid sand landing refreshes it.
- A restrained HUD communicates speed, descent, distance, controls, and boost state.
- Mouse/right-stick orbit controls retain the existing free camera behavior.

The previous movement-survivor scene remains in `main.tscn` only as temporary migration reference. It is not the project entry scene and its combat/progression systems are outside the new game direction.

This is still a foundation, not the completed game. Repeated terrain-shape iteration, sandboard animation and contact physics, more landmark and gap variety, environmental audio, effects, accessibility, long-session streaming/performance soaks, and external playtest validation remain required.

## Controls

- `W` / `A` / `S` / `D` or left stick: carve relative to the camera
- Mouse or right stick: orbit the camera independently
- `Space` or gamepad `A`: jump
- `Shift` / `Alt` or either shoulder button: use the single directional air boost while airborne
- `Escape` or Start: pause

## Architecture

- `procedural_desert.gd` owns seeded radial terrain generation, seamless visual/collision chunks, bounded streaming, and floating-origin rebasing.
- `desert_feature_grammar.gd` owns the deterministic, cache-bounded macro-feature distribution and its smooth analytic landforms.
- `sandboarder.gd` owns slope-driven movement, carving, air control, jump/landing transitions, and boost application.
- `air_boost_state.gd` owns the small testable one-charge, sand-only refresh contract.
- `follow_camera.gd` owns independent mouse/right-stick orbit and speed feedback.
- `freeride_main.gd` owns the minimal run lifecycle, onboarding, pause flow, and HUD.
- `main.tscn` and the older survivor scripts/tests are legacy migration material and are not loaded by the freeride runtime.

## Focused validation

Run the boost-state contract, combat-free runtime integration, radial terrain sweep, input mapping, and project boot checks with:

```sh
godot --headless --path games/overrush --script res://tests/test_air_boost_state.gd
godot --headless --path games/overrush --script res://tests/test_desert_feature_grammar.gd
godot --headless --path games/overrush --script res://tests/validate_freeride_runtime.gd
godot --headless --path games/overrush --script res://tests/validate_desert_terrain.gd
godot --headless --path games/overrush --script res://tests/validate_desert_streaming.gd
godot --headless --fixed-fps 300 --path games/overrush --script res://tests/validate_sandboard_motion.gd
godot --headless --path games/overrush --script res://tests/test_input_bindings.gd
godot --headless --path games/overrush --quit-after 12
```

The feature gate checks deterministic seed variation, balanced feature-family distribution, smooth cell boundaries, bounded cache residency, meaningful relief, and a maximum authored-feature grade. The terrain sweep samples 16 radial lines over 12 km and requires every heading's reachable 512 m-wide line fan to encounter bowls, ridges, kickers, split lines, and multiple rock passages while rejecting insufficient net descent, non-finite terrain, repetitive cone geometry, or abrupt local rises. The streaming gate compares adjacent mesh borders and normals, raycasts both sides of a collision seam, verifies rock clearance and non-sand identity, simulates 22 km of repeated rebased travel, and checks the collision safety neighborhood plus bounded chunk residency throughout. These automated gates establish a foundation; they do not substitute for long-session streaming soaks or hands-on movement playtests.
