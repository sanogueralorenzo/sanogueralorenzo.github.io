# Shared procedural components

Map generators compose these components. Layout coordinates, placement exclusions, seeds, palettes, artistic profiles and unique features belong under `maps/<id>/`. Shared components neither look up a map ID nor depend on another map's scripts.

| Component | Owns | Existing differences supplied by callers |
| --- | --- | --- |
| `primitives.gd` | Box, sphere and cylinder meshes; mesh instances; beams | Dimensions, tessellation, transforms and materials; Harbor batches unit meshes while Seabreeze builds then merges props |
| `collision.gd` | Box and triangle-mesh collision shapes | Existing static or animatable body, shape size and rotation; independent prop bodies where needed |
| `mesh_batches.gd` | Stable spatial grouping, local instance transforms, draw distance and shadow batches; static mesh merging | Seabreeze foliage uses 24 m cells, architecture 32 m; Harbor primitives use 40 m cells and grass 32 m; separate draw/shadow distances remain explicit |
| `solid_materials.gd` | Per-owner toon material cache | Palette colors remain with the owning map or character; mutable materials are not global singletons |
| `leaf_painter.gd` | Bounded image rasterization for rounded and pointed leaf silhouettes | Profile, center, dimensions, orientation, shade and outline; distributions and random draws remain map-owned |
| `atmosphere.gd` | Sky, ambient light, sun, optional fill, depth fog, ocean and screen paint | Each map's `atmosphere.tres` supplies its palette, lighting, fog, ocean extent and paint radius |
| `air_particles.gd` | Box emitters and procedural particle mesh/material | Each map's `air.tres` supplies quantity, motion, scale, shape and color; emitter positions stay in the map |
| `scene_cache.gd` | Source signatures, recursive scene ownership, saving and restoring generated branches | Map folder and cache namespace; each map decides which content is static |

## Change a shared mechanic

Edit the owning component, then inspect both destinations using the native capture commands in the project README. Keep RNG draws in the same order: shared rasterization and batching do not draw random numbers. Spatial groups preserve insertion order; rebasing instance transforms and visibility margins are part of the visual/performance contract. Static merging retains collision siblings, labels, and the explicit excluded animation roots.

Cache signatures include sorted paths and contents for generation sources (`gd`, `gdshader`, `gdshaderinc`, `tres`, `tscn`) in the selected map folder, `shared/`, and common `shaders/`. A shared source change invalidates both maps. A map source change invalidates only that map. Added helper files within those folders are included automatically. UIDs, documentation, previews and generated files do not influence the signature. Terrain/layout resources and packed foliage/district scenes keep separate cache namespaces. Never store characters or active map instances in these caches.

## Change map content

Edit that map's generator or profile. Both maps intentionally retain different terrain algorithms, plant shapes, grass topology, texture recipes and building styles. Harbor's shader-based building finishes and Seabreeze's image-based finishes are different artistic systems; forcing them into a shared material would change the result. Vehicles, buildings, parks, paddies, shrine, railway and route animation likewise remain local and use common construction mechanisms.

Common movement, camera, input, synthesized character/ambient audio and UI remain in `scripts/`. The `CozyMap` interface supplies ground queries, ambience, flight bounds and the opt-in surface-traversal policy. Add a clear capability there only when common gameplay actually needs it; do not branch on map names in the player.
