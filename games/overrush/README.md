# Overrush

Map-first prototype for a fast 3D run across large procedural landscapes.

## Current scope

- A newly randomized 3.2 km × 3.2 km terrain on every run.
- A route graph generated before the terrain, with occasional alternate paths that split and merge.
- Authored terrain features: broad valleys, banked turns, launch hills, smooth landing zones, and narrow passes.
- Three blended regions per run: Verdant Reach, Ember Basin, and Prism Highlands.
- Original rock spires, boulder fields, distant ridges, and procedural materials.
- Route geometry designed to preserve readable 200–400 meter sightlines at high speed.
- A small auto-running ball and follow camera used only to test terrain flow and scale.

The prototype intentionally contains no enemies, combat, progression, pickups, or character systems.

## Controls

- `A` / `D` or left / right: steer
- `W` or up: boost
- `S` or down: brake
- `Space`: hop
- `R`: generate a new world

## Map validation

Run the deterministic 20-seed terrain and formation gate with:

```sh
godot --headless --path games/overrush --script res://tests/validate_worlds.gd
```

The gate checks required terrain shapes, route continuity and slopes, sightline curvature, alternate-route frequency, formation clearance, finite terrain heights, three-region coverage, and layout uniqueness.
