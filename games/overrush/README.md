# Overrush

Map-first prototype for a fast 3D run across large procedural landscapes.

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

The prototype intentionally contains no enemies, combat, progression, pickups, or character systems.

## Generation architecture

- `route_generator.gd` owns deterministic route topology and authored feature samples.
- `route_lookup.gd` converts route samples into packed Z buckets for allocation-free height queries.
- `terrain_grammar.gd` owns noise, regional blending, and route-shaped terrain heights.
- `terrain_validator.gd` keeps test-only safety checks out of runtime generation code.

## Controls

- `A` / `D` or left / right: steer
- `W` or up: boost
- `S` or down: brake
- `Space`: hop
- `Shift` or `Alt`: dash (tap for a short burst, hold for maximum distance)
- `R`: generate a new world

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
