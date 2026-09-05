# Seabreeze Village

All coastal layout and generation now live beside this map's scene and definition.

- `world.gd`: terrain and road queries, road/rail layout, coastal props, generation stages and cache composition.
- `settlements.gd`: authored building, farm, paddy, shrine, vending and railway construction; train and butterfly animation. Moving roots are excluded from shared static merging.
- `finishes.gd`: image-generated wood, paint, tile, stone and chain-link finishes with a map-owned material cache.
- `vegetation.gd`: seeded placement, clearings, landmark flora, local plant assemblies and visibility policy.
- `plant_meshes.gd`: canopy, branch, bush, pine-tier and curved-grass geometry. It receives the placement generator's existing random stream so extraction preserves draw order.
- `textures.gd`: leaf, flower, pine, bark and shrine texture recipes. Leaf silhouettes use the shared rasterizer.
- `seeded_random.gd`: the existing deterministic 32-bit generator, including explicit `self.randf()` calls and restorable state. It differs intentionally from Harbor's Godot RNG.
- `summer_life.gd`: butterfly placements and movement, plus the local pollen emitter position.
- `atmosphere.tres`, `air.tres`: artistic parameters for the shared atmosphere and particle components.
- `terrain.gdshader`, `rice_blades.gdshader`, `rice_canopy.gdshader`: map-specific ground and paddy shading.

See [shared component ownership](../../shared/README.md) before changing construction mechanics. Change placements, seeds and palettes here. Common player, camera, input and audio behavior remains under `scripts/` and uses the [map contract](../../MAPS.md).
