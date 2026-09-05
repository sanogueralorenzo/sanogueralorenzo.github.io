# Daan Gardens

A compact fictional urban park inspired by Taipei's Daan Forest Park: a living pond, bird island, spreading banyans, bamboo walks, an open lawn and a small neighborhood of tiled apartments. It shares Cozy Sora's characters, controls, rendering style and scale. The reference informed the park's ecology and character; this is an original playable composition, not a survey of the real park.

## Explore

Begin at the stone entrance marker. The central path leads toward the pond and around the lawn, with a smaller loop following the bank. A low boardwalk reaches the viewing deck. The bird island is accessible in flight, while the cat stays on dry ground and the deck. Beyond the pond, paths meet at a banyan court with circular seating and an open tea pavilion. Bamboo and planted pockets frame quieter shortcuts.

Across the east street, eight apartment buildings contain open café entrances, interior counters and seating, striped awnings, tiled walls, balconies, barred windows, air conditioners and rooftop water tanks. Shared side courts connect the frontage to the service alley. Scooters gather beside the sidewalk. A continuous ground skirt and surrounding streets place the park inside a hazy fictional city.

Movement uses the shared keyboard, gamepad and touch controls. The seagull can perch on physical roofs, branches and the deck. Switching to the cat requires a clear safe surface; unsuitable water positions recover to safe ground. Map simulation and synthesized ambience pause with the shared menu.

## Construction and ownership

- `world.gd` owns the height/walkability contract, Catmull–Rom path network, pond and island outline, collision terrain, paving, scenic viewpoints, cache and animated egrets.
- `geometry.gd` composes shared primitive meshes, collision helpers and spatial batches. Ribbons use joined vertices and sample terrain at both edges. Planar access ramps preserve their authored grade.
- `planting.gd` paints leaf sprays into generated image textures, builds varied tapered branching and roots, distributes crowns and understory, and creates bamboo, fern fronds, reeds, lilies and short lawn grass. Major wooden limbs have oriented capsule collisions. Grass and small leaves bend near the player through the shared shaders.
- `neighborhood.gd` owns tiled apartment composition, accessible cafés, façade details, courtyards, scooters and muted skyline buildings.
- `furnishings.gd` owns slatted benches, lamps, bins, signs, stone banks, the deck and the pavilion's tiled hip roof and wooden underside.
- `ground.gdshader`, `surface.gdshader` and `pond.gdshader` provide smooth ground variation, correctly oriented finish patterns and calm moving pond reflections. Screen-space reflections are enabled only for this map.
- `atmosphere.tres` and `air.tres` configure the shared summer lighting, haze, painterly post effect and drifting seed particles. The shared player synthesizes local wind, cicadas and birds; no audio files are used.

Static meshes, generated textures and collision shapes are packed into `user://daan_gardens_<signature>.scn`. Source changes in this map or shared components invalidate that cache. Environment, particles and animated birds are recreated for each visit. No player, camera, UI, audio stream or live map instance is cached.

All content is authored in GDScript and Godot shaders or constructed from engine primitives. No external models, textures, animations, visual assets or audio are imported.

Reference: [Taipei Travel's Daan Forest Park guide](https://www.travel.taipei/en/media/audio-guide/details/230), describing the park's subtropical trees and ecological pond.

`preview.png` is an unmodified 1280 × 720 native render of the `pond` viewpoint. All visible content comes from this project’s generators.
