# Harbor Hills

A fictional 360 × 360 m summer district, with four connected blocks rising from a northern bay to a wooded western ridge. All geometry, foliage, shaders, signs, motion and audio are authored or generated within Cozy Sora. No city data or external assets are used.

## Explore

Start beside the main-street café. Follow the rails down to the promenade, pier, boat shed and small post kiosk, or uphill through the shops to the turning plaza. Row houses face the cross streets, with garages, projecting windows, striped awnings, fire escapes and roof gardens. Narrow lanes lead to pergolas, laundry, potting plots and low workshop roofs. Two stair streets connect to cypress paths and an overlook. The seagull can settle on roofs and fly out over the bay; switching back requires a clear, traversable surface.

Movement and menu controls are shared with Seabreeze Village: WASD, mouse look, Space to jump/climb, C/Ctrl to descend, Shift to sprint/boost, Tab to switch, Escape for the menu. Touch and gamepad controls use the same shared interface. There is no separate transit interaction button: the cable car is a moving physical part of the neighborhood.

## Construction

- `world.gd`: terrain, ground contract, terrain-draped streets/sidewalks, rails, lighting, water, moving fog, static cache and scenic views.
- `geometry.gd`: material and mesh generation, spatially batched primitives, labels, collision and ribbon surfaces. Ordinary ribbon edges sample ground independently; authored access ramps and stairs preserve their intended planes.
- `neighborhood.gd`: shared building-plot definitions, façades, grounded foundations, street-connected forecourts, roof routes, shop displays, café furniture, yards, stairs, utility wires and parked vehicles.
- `nature.gd`: wind-shaped cypress and rounded street trees, curved grass, wildflowers, park paths, overlook, surrounding land, fictional far shore, suspension bridge and shaped boat hulls with rigged sails.
- `details.gd`: planted street edges, bicycles, stoops, market displays, communal garden tables, retaining borders, shaded waterfront seating and dock fittings.
- `textures.gd`: deterministic leaf-spray textures painted into runtime images; no image files are imported for foliage.
- `transit.gd`: cable car with stops at waterfront, lower shops, upper neighborhood and hilltop; a continuous 160-second round trip with dwell and turning phases; restrained vehicle activity; background birds; synthesized bell.
- `surface.gdshader`, `ground.gdshader`, `leaves.gdshader`, `cloth.gdshader`, `fog.gdshader`: painted finish variation, fitted stone on steep cuts, textured leaf wind, pinned laundry and moving coastal wisps. The project-owned sky, ocean, grass and painterly post shaders are reused. Sparse GPU seed particles drift around the gardens.

Main uphill streets run at X = −76, 8 and 90 m. Cross streets run at Z = −102, −32, 46 and 106 m. The eleven outer street ends use semicircular asphalt and continuous curved sidewalks, with planting kept clear of the curves. The waterfront is at Z ≈ −119 m, and the park occupies the western and upper district. Non-playable procedural land continues beyond the district so the neighborhood belongs to a larger fictional city.

The map owns its generated content and special behavior. Its registry definition supplies presentation and spawn data; the application supplies a disposable gameplay session and the shared characters, camera, UI, settings and ambient synthesizer. See the project [map lifecycle](../../MAPS.md) and [verification record](../../VERIFICATION.md).

`preview.png` is an unmodified 1280 × 720 native render of the map's `cable_car` viewpoint, captured on 5 September 2026 using the final procedural generators. It contains only project-owned content.

The current planting includes 288 trees and 295,676 five-blade grass clumps in 83 spatial batches. Grass draws within 110 m of its batch, with a 12 m visibility margin. Trees cast broken shade across the main street; flower beds occupy the curb edge while crossings and sidewalk routes stay open. Building plots are set back within their existing blocks, uphill soil is cut to their occupied level, and foundations extend down to the original terrain. Forecourt ramps meet the nearest sidewalk. A small Harbor-only character recovery margin prevents capsule contact from sticking on sloped mesh seams.
