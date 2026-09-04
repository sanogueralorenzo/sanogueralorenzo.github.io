# Harbor Hills

A fictional 360 × 360 m summer district, with four connected blocks rising from a northern bay to a wooded western ridge. All geometry, foliage, shaders, signs, motion and audio are authored or generated within Cozy Sora. No city data or external assets are used.

## Explore

Start beside the main-street café. Follow the rails down to the promenade, pier, boat shed and small post kiosk, or uphill through the shops to the turning plaza. Row houses face the cross streets, with garages, projecting windows, striped awnings, fire escapes and roof gardens. Narrow lanes lead to pergolas, laundry, potting plots and low workshop roofs. Two stair streets connect to cypress paths and an overlook. The seagull can settle on roofs and fly out over the bay; switching back requires a clear, traversable surface.

Movement and menu controls are shared with Seabreeze Village: WASD, mouse look, Space to jump/climb, C/Ctrl to descend, Shift to sprint/boost, Tab to switch, Escape for the menu. Touch and gamepad controls use the same shared interface. There is no separate transit interaction button: the cable car is a moving physical part of the neighborhood.

## Construction

- `world.gd`: terrain, ground contract, terrain-draped streets/sidewalks, rails, lighting, water, moving fog, static cache and scenic views.
- `geometry.gd`: material and mesh generation, spatially batched primitives, labels, collision and ribbon surfaces. Ordinary ribbon edges sample ground independently; authored access ramps and stairs preserve their intended planes.
- `neighborhood.gd`: façades, roof routes, shop displays, café furniture, yards, stairs, utility wires, parked vehicles and waterfront activity.
- `nature.gd`: wind-shaped cypress with procedural leaf cards, grass, wildflowers, park paths, overlook, surrounding land, fictional far shore, suspension bridge and boats.
- `transit.gd`: cable car with stops at waterfront, lower shops, upper neighborhood and hilltop; a continuous 160-second round trip with dwell and turning phases; restrained vehicle activity; background birds; synthesized bell.
- `surface.gdshader`, `leaves.gdshader`, `fog.gdshader`: original finish grain/siding, leaf/grass wind and moving coastal wisps. The project-owned sky, ocean and painterly post shaders are reused.

Main uphill streets run at X = −76, 8 and 90 m. Cross streets run at Z = −102, −32, 46 and 106 m. The waterfront is at Z ≈ −119 m, and the park occupies the western and upper district. Non-playable procedural land continues beyond the district so the neighborhood belongs to a larger fictional city.

The map owns its generated content and special behavior. Its registry definition supplies presentation and spawn data; the application supplies a disposable gameplay session and the shared characters, camera, UI, settings and ambient synthesizer. See the project [map lifecycle](../../MAPS.md) and [verification record](../../VERIFICATION.md).

`preview.png` is an unmodified 1280 × 720 native render of the map's `cable_car` viewpoint, captured on 4 September 2026 using the final procedural generators. It contains only project-owned content.
