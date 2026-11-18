# Shared procedural components

Map generators compose these components. Layout coordinates, placement exclusions, seeds, palettes, artistic profiles and unique features belong under `maps/<id>/`. Shared components neither look up a map ID nor depend on another map's scripts.

| Component | Owns | Existing differences supplied by callers |
| --- | --- | --- |
| `CozyPrimitives.cs` | Box, sphere and cylinder meshes; mesh instances; beams | Dimensions, tessellation, transforms and materials; Harbor batches unit meshes while Seabreeze builds then merges props |
| `CozyCollision.cs` | Box, capsule-limb and triangle-mesh collision shapes | Existing static or animatable body, shape size and rotation; independent prop bodies where needed |
| `CozyMeshBatches.cs` | Stable spatial grouping, local instance transforms, draw distance and shadow batches; static mesh merging | Seabreeze foliage uses 24 m cells, architecture 32 m; Harbor primitives use 40 m cells and grass 32 m; separate draw/shadow distances remain explicit |
| `CozySolidMaterials.cs` | Per-owner material cache | Palette colors remain with the owning map or character; mutable materials are not global singletons |
| `CozyLeafPainter.cs` | Leaf silhouettes and seeded twig sprays | Leaf shape, scale and palette |
| `CozyGrassMesh.cs` | Curved, tapered grass clumps | Seed, blade count and width |
| `CozyBark.cs`, `CozyGlazing.cs` | Procedural bark relief and opaque reflective glazing | Tint and bark groove scale |
| `CozyAtmosphere.cs` | HDR cloud panorama, ambient light, sun, fill, depth fog and ocean | Each map's `atmosphere.tres` supplies its palette, lighting, fog and ocean extent |
| `CozyAirParticles.cs` | Box emitters and procedural particle mesh/material | Each map's `air.tres` supplies quantity, motion, scale, shape and color; emitter positions stay in the map |
| `CozySceneCache.cs` | Source signatures, recursive scene ownership, saving and restoring generated branches | Map folder and cache namespace; each map decides which content is static |

## Change a shared mechanic

Edit the owning component, then inspect all destinations using the native capture commands in the project README. Spray and grass mesh generation use their own seeded streams. Keep the map placement streams separate. Spatial groups preserve insertion order; rebasing instance transforms and visibility margins are part of the visual/performance contract. Static merging retains collision siblings, labels, and the explicit excluded animation roots.

Cache signatures include sorted paths and contents for generation sources (`cs`, `gdshader`, `gdshaderinc`, `tres`, `tscn`) in the selected map folder, `shared/`, and common `shaders/`. A shared source change invalidates all maps. A map source change invalidates only that map. Added helper files within those folders are included automatically. UIDs, documentation, previews and generated files do not influence the signature. Terrain/layout resources and packed foliage/district scenes keep separate cache namespaces. Never store characters or active map instances in these caches.

## Change map content

Summer lighting, two blended shadow cascades and contact occlusion live in `CozyAtmosphere.cs` and the map profiles. Medium PCF filtering and FXAA keep broad pavement shadows smooth without temporal accumulation or contact-distance dithering. Keep the depth bias high enough to avoid self-shadow interference between thin paving and terrain; tune normal bias per map before changing material patterns. `surface_noise.gdshaderinc` supplies derivative-filtered variation, surface relief and integrated paving joints, retaining detail near the camera without distant shimmer. Foliage normals use the normal matrix so stretched instances keep their intended crown lighting. `CozyCollision.Limb` aligns capsule support with tapered or bent wooden segments.

Edit that map's generator or profile. Each map defines its terrain, planting, building forms and finish patterns. Shared shader functions supply surface relief and runoff. Vehicles, buildings, parks, paddies, shrine, railway and route animation likewise remain local and use common construction mechanisms.

Common movement, camera, input, synthesized character/ambient audio and UI remain in `scripts/`. The `CozyMap` interface supplies ground queries, ambience, flight bounds and the opt-in surface-traversal policy. Add a clear capability there only when common gameplay actually needs it; do not branch on map names in the player.
