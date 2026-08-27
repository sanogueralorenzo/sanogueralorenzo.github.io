# Overrush

Early movement-survivor prototype for fast combat runs across large procedural landscapes.

## Current scope

- A newly randomized 3.2 km × 3.2 km terrain on every run.
- A route graph generated before the terrain, with occasional alternate paths that split and merge.
- Authored terrain features: broad valleys, banked turns, gradual launch hills, smooth landing zones, and gently shouldered narrow passes.
- Three blended regions per run: Verdant Reach, Ember Basin, and Prism Highlands.
- Original rock spires, boulder fields, distant ridges, and procedural materials.
- Route geometry designed to preserve readable 200–400 meter sightlines at high speed.
- Packed Z-bucket route lookups and heightmap collision keep full world generation responsive.
- A small auto-running ball and follow camera used to test terrain flow, scale, and high-speed traversal.
- A short, hold-sensitive dash that is repeatable on the ground and available once per airtime.
- A speed-aware perimeter jetstream that smoothly banks traversal back across the landscape instead of using invisible walls or abrupt terrain obstructions.
- Momentum-preserving steering and glancing collision response prevent high-speed turns or scenery contact from stopping the run.
- Terrain-aware Pursuer, Skimmer, and Bulwark threats with escalating population and durability.
- Skimmer charges and Bulwark pulses use ground telegraphs before their damaging windows; scheduled elites amplify those patterns without removing the warning.
- A homing arc weapon, collectible experience, integrity damage, run timer, and defeat state.
- A first level-up commitment to one exclusive movement-centric engine: Dashbreaker, Stormtrail, or Arcstorm.
- Path-specific follow-ups create different combat geometry: dash entry/exit detonations and immunity, persistent traversal wakes, or speed-scaled multi-target chain arcs.
- A structured 20-minute run: Breakaway, Pressure Rises, Redline, Overrun, and a two-minute Apex climax with explicit victory or deadline failure.
- A run-launch screen summarizes persistent Momentum, completed runs, victories, best survival time, and the selected challenge protocol.
- Recovery-safe, versioned profile saving keeps a previous valid backup and restores it if the primary save is missing or corrupt.
- Momentum unlocks optional run protocols rather than permanent combat power: denser Redline spawns, high-risk Glass Velocity damage, and elite-heavy hunts each trade added pressure for larger rewards.

This is not yet the complete target game. The 20-minute structure, first boss, and initial non-power-creeping progression loop now exist, but broad content variety, audio, accessibility, repeated balance work, onboarding/usability validation, and external playtesting remain long-term work.

## Generation architecture

- `route_generator.gd` owns deterministic route topology and authored feature samples.
- `route_lookup.gd` converts route samples into packed Z buckets for allocation-free height queries.
- `terrain_grammar.gd` owns noise, regional blending, and route-shaped terrain heights.
- `terrain_validator.gd` keeps test-only safety checks out of runtime generation code.
- `combat_director.gd` owns spawning, escalation, targeting, rewards, and movement-triggered combat effects.
- `run_build.gd` owns testable experience thresholds, exclusive upgrade pools, and build-changing path state.
- `run_pacing.gd` owns the deterministic phase, elite, Apex, and deadline schedule independently of frame rate.
- `run_protocols.gd` is the single catalog for challenge tradeoffs, reward multipliers, and Momentum thresholds.
- `progress_profile.gd` owns versioned progression state, deterministic run rewards, protocol selection, atomic writes, and backup recovery.

## Controls

- `A` / `D` or left / right: steer
- `W` or up: boost
- `S` or down: brake
- `Space`: hop
- `Shift` or `Alt`: dash (tap for a short burst, hold for maximum distance)
- `R`: generate a new world
- `1` / `2` / `3` or mouse: choose a level-up upgrade
- At the launch screen, `A` / `D` or left / right changes protocol and `Enter` / `Space` starts the run

## Map validation

Run the deterministic 20-seed terrain and formation gate with:

```sh
godot --headless --path games/overrush --script res://tests/validate_worlds.gd
```

The gate checks required terrain shapes, route continuity and slopes, local corridor gradients, sightline curvature, alternate-route frequency, formation clearance, finite terrain heights, three-region coverage, and layout uniqueness.

Run the deterministic regular/alternate generation performance gate with:

```sh
godot --headless --path games/overrush --script res://tests/benchmark_generation.gd
```

The current development-machine target is less than two seconds for a complete 321 × 321 world.

Run the terrain collision and grounded-runner integration check with:

```sh
godot --headless --path games/overrush --script res://tests/validate_heightmap_collision.gd
```

Run the dash timing and ground/air reset checks with:

```sh
godot --headless --path games/overrush --script res://tests/test_dash_state.gd
```

Run the build rules and playable combat integration checks with:

```sh
godot --headless --path games/overrush --script res://tests/test_run_build.gd
godot --headless --path games/overrush --script res://tests/validate_combat_slice.gd
godot --headless --path games/overrush --script res://tests/validate_build_paths.gd
```

Run the simulated 20-minute and in-engine maximum-speed boundary traversal checks with:

```sh
godot --headless --path games/overrush --script res://tests/test_boundary_current.gd
godot --headless --path games/overrush --script res://tests/validate_boundary_runtime.gd
```

Run the timed phase model and accelerated elite/Apex outcome checks with:

```sh
godot --headless --path games/overrush --script res://tests/test_run_pacing.gd
godot --headless --path games/overrush --script res://tests/validate_run_climax.gd
```

Run the persistent-profile and challenge-protocol checks with:

```sh
godot --headless --path games/overrush --script res://tests/test_progress_profile.gd
godot --headless --path games/overrush --script res://tests/validate_run_protocols.gd
```
