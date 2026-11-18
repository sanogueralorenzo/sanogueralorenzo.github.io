# Seabreeze Village

All coastal layout and generation now live beside this map's scene and definition.

- `SeabreezeWorld.cs` and `SeabreezeWorld.Props.cs`: terrain and road queries, road/rail layout, coastal props, generation stages and cache composition.
- `SeabreezeSettlements.cs`: authored building, farm, paddy, shrine, vending and railway construction; train and butterfly animation. Moving roots are excluded from shared static merging.
- `SeabreezeFinishes.cs`: procedural timber, plaster, roof tile, masonry, glazing and chain-link finishes with a map-owned material cache.
- `SeabreezeVegetation.cs`: seeded placement, clearings, landmark flora, local plant assemblies and visibility policy.
- `SeabreezePlantMeshes.cs`: curved trunks with root flares, smaller limbs with attached foliage, individual leaves on the closest coastal trees, bush crowns and pine tiers.
- `SeabreezeHydrangeas.cs`: seeded stems, serrated leaves and cupped florets at the roadside. Inspect the details with the `hydrangeas` scenic view.
- `SeabreezeTextures.cs`: leaf, flower, pine and shrine texture recipes. Leaf silhouettes use the shared rasterizer.
- `SeabreezeRandom.cs`: the existing deterministic 32-bit generator, using unchecked Mulberry32 arithmetic, double-precision random fractions and restorable state. It differs intentionally from Harbor's Godot RNG.
- `SeabreezeSummerLife.cs`: butterfly placements and movement, plus the local pollen emitter position.
- `atmosphere.tres`, `air.tres`: artistic parameters for the shared atmosphere and particle components.
- `architecture.gdshader`, `terrain.gdshader`, `rice_blades.gdshader`, `rice_canopy.gdshader`, `giant_bark.gdshader`: map-specific building, ground and paddy shading. The coastal props use separate galvanized steel and weathered concrete shaders.

See [shared component ownership](../../shared/README.md) before changing construction mechanics. Change placements, seeds and palettes here. Common player, camera, input and audio behavior remains under `scripts/` and uses the [map contract](../../MAPS.md).
