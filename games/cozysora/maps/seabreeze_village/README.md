# Seabreeze Village

All coastal layout and generation now live beside this map's scene and definition.

- `SeabreezeWorld.cs` and `SeabreezeWorld.Props.cs`: terrain and road queries, road/rail layout, coastal props, generation stages and cache composition.
- `SeabreezeSettlements.cs`: authored building, farm, paddy, shrine, vending and railway construction; train and butterfly animation. Moving roots are excluded from shared static merging.
- `SeabreezeFinishes.cs`: image-generated wood, paint, tile, stone and chain-link finishes with a map-owned material cache.
- `SeabreezeVegetation.cs`: seeded placement, clearings, landmark flora, local plant assemblies and visibility policy.
- `SeabreezePlantMeshes.cs`: canopy, branch, bush, pine-tier and curved-grass geometry. It receives the placement generator's existing random stream so extraction preserves draw order.
- `SeabreezeTextures.cs`: leaf, flower, pine, bark and shrine texture recipes. Leaf silhouettes use the shared rasterizer.
- `SeabreezeRandom.cs`: the existing deterministic 32-bit generator, using unchecked Mulberry32 arithmetic, double-precision random fractions and restorable state. It differs intentionally from Harbor's Godot RNG.
- `SeabreezeSummerLife.cs`: butterfly placements and movement, plus the local pollen emitter position.
- `atmosphere.tres`, `air.tres`: artistic parameters for the shared atmosphere and particle components.
- `terrain.gdshader`, `rice_blades.gdshader`, `rice_canopy.gdshader`, `giant_bark.gdshader`: map-specific ground and paddy shading.

See [shared component ownership](../../shared/README.md) before changing construction mechanics. Change placements, seeds and palettes here. Common player, camera, input and audio behavior remains under `scripts/` and uses the [map contract](../../MAPS.md).
