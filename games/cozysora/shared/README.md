# Shared procedural components

Map generators compose these components. Layout coordinates, placement exclusions, seeds, palettes, artistic profiles and unique features belong under `maps/<id>/`. Shared components neither look up a map ID nor depend on another map's scripts.

| Component | Owns | Existing differences supplied by callers |
| --- | --- | --- |
| `CozyPrimitives.cs` | Box, sphere and cylinder meshes; mesh instances; beams | Dimensions, tessellation, transforms and materials; Harbor batches unit meshes while Seabreeze builds then merges props |
| `CozyCollision.cs` | Box, capsule-limb and triangle-mesh collision shapes | Existing static or animatable body, shape size and rotation; independent prop bodies where needed |
| `CozyMeshBatches.cs` | Stable spatial grouping, local instance transforms, draw distance and shadow batches; static mesh merging | Seabreeze foliage uses 24 m cells, architecture 32 m; Harbor primitives use 40 m cells and grass 32 m; separate draw/shadow distances remain explicit |
| `CozySolidMaterials.cs` | Per-owner toon material cache | Palette colors remain with the owning map or character; mutable materials are not global singletons |
| `CozyLeafPainter.cs` | Bounded image rasterization for rounded and pointed leaf silhouettes | Profile, center, dimensions, orientation, shade and outline; distributions and random draws remain map-owned |
| `CozyAtmosphere.cs` | Sky, ambient light, sun, optional fill, depth fog, ocean and screen paint | Each map's `atmosphere.tres` supplies its palette, lighting, fog, ocean extent and paint radius |
| `water/` | Shared C# wave spectrum, adaptive ocean mesh, bathymetry, water material and seagull support | Map-owned sea, pond and paddy profiles and terrain samplers; see [water notes](water/README.md) |
| `CozyAirParticles.cs` | Box emitters and procedural particle mesh/material | Each map's `air.tres` supplies quantity, motion, scale, shape and color; emitter positions stay in the map |
| `CozySceneCache.cs` | Source signatures, recursive scene ownership, saving and restoring generated branches | Map folder and cache namespace; each map decides which content is static |

## Change a shared mechanic

Edit the owning component, then inspect all destinations using the native capture commands in the project README. Keep RNG draws in the same order: shared rasterization and batching do not draw random numbers. Spatial groups preserve insertion order; rebasing instance transforms and visibility margins are part of the visual/performance contract. Static merging retains collision siblings, labels, and the explicit excluded animation roots.

Cache signatures include sorted paths and contents for generation sources (`cs`, `gdshader`, `gdshaderinc`, `tres`, `tscn`) in the selected map folder, `shared/`, and common `shaders/`. A shared source change invalidates all maps. A map source change invalidates only that map. Added helper files within those folders are included automatically. UIDs, documentation, previews and generated files do not influence the signature. Terrain/layout resources and packed foliage/district scenes keep separate cache namespaces. Never store characters or active map instances in these caches.

Packed scene caching is disabled in headless mode, including Harbor’s direct scene load. Godot’s dummy renderer discards the per-instance MultiMesh transform writes used by our batching code; saving those scenes can leave later native runs without buildings or vegetation. Headless runs build their scenes in memory and do not replace native scene caches. The separately cached terrain arrays and layout images retain CPU-backed data. A successful headless map load does not verify rendered instance data: inspect native generation and a native cache reload when validating visual changes.

## Change map content

Each map’s installed `SummerSun` is the source of truth for sun direction. `CozyAtmosphere.DirectionToSun` reads its normalized global +Z after the map’s authored transform; Godot emits directional light along −Z. The sky material and every water surface receive that same world-space direction when constructed. The sky’s sun glow, directional cloud shading and reflected sky therefore agree with the map’s direct lighting. Materials are created per map, and the optional fill light is not used as the sun. Directions are fixed for these summer maps; a future moving-sun feature would need to refresh both materials. See [Godot’s directional-light convention](https://docs.godotengine.org/en/latest/classes/class_directionallight3d.html).

The shared sky keeps its cloud density field, animation and warm/cool palette. Cloud edges blend across ±0.010 of the density threshold, with a small 0.12 contribution from the four-band shading and a centered 0.12–0.48 main tone transition. These restrained transfer-function changes soften contours without extra noise samples or separate background/reflection logic.

Summer lighting, two blended shadow cascades, restrained contact occlusion and the painterly post effect live in `CozyAtmosphere.cs` and the map profiles. Medium PCF filtering and FXAA keep broad pavement shadows smooth without temporal accumulation or contact-distance dithering. Keep the depth bias high enough to avoid self-shadow interference between thin paving and terrain; tune normal bias per map before changing material patterns. `surface_noise.gdshaderinc` supplies continuous, derivative-filtered variation and integrated paving joints, retaining detail near the camera without distant shimmer. Foliage normals use the normal matrix so stretched instances keep their intended crown lighting. `CozyCollision.Limb` aligns capsule support with tapered or bent wooden segments.

Edit that map's generator or profile. The maps intentionally retain different terrain algorithms, plant shapes, grass topology, texture recipes and building styles. Harbor's shader-based building finishes and Seabreeze's image-based finishes are different artistic systems; forcing them into a shared material would change the result. Vehicles, buildings, parks, paddies, shrine, railway and route animation likewise remain local and use common construction mechanisms.

Common movement, camera, input, synthesized character/ambient audio and UI remain in `scripts/`. The `CozyMap` interface supplies ground queries, ambience, flight bounds and the opt-in surface-traversal policy. Add a clear capability there only when common gameplay actually needs it; do not branch on map names in the player.

## Procedural vegetation forms

`CozyTreeForms` owns only reusable woody geometry: gently irregular tapered limbs and continuous buttressed root collars. Root collars sample the map terrain around their perimeter, bury the outer edge and blend into the trunk. Their outward-wound mesh also supplies collision where substantial roots are exposed. The shrine grounds its existing continuous trunk flare and derives basal collision from those exact vertices, avoiding an overlapping collar or bark seam.

Each map retains its own planting and canopy recipe. Daan varies broad banyans, narrower upright crowns and spreading evergreens; branches and sparse aerial roots attach to the same bent centerline used by the visible limb. Harbor varies crown proportions, tier spacing, lean and branch phase, with a dedicated procedural bark finish. Seabreeze retains its authored pine/broadleaf composition while adding fork variation and keeping small-shrub woody tips inside their crown. Coordinate-derived variation and preserved random draw counts keep existing placement streams stable; Seabreeze also retains its original spacing radii. Foliage continues to use generated leaf textures, wind shaders and spatial instance batches.
