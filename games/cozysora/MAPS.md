# Cozy Sora map registry and lifecycle

## Registry

`maps/registry.tres` is a `CozyMapRegistry` resource with an ordered array of `CozyMapDefinition` resources. The landing screen reads that array; it contains no map IDs, scene paths, descriptions, or previews of its own. IDs must be unique and stable. Every registered entry must be playable and provide a scene and preview.

A definition supplies `id`, `title`, `subtitle`, `description`, `scene`, `preview`, `spawn_position`, `spawn_yaw`, `spawn_pitch`, and `spawn_mode`. Position X/Z are map coordinates. Position Y is an offset above `height_at(X,Z)`. Camera angles are radians; spawn mode is `cat` or `gull`.

## Scene contract

A map scene's root extends `CozyMap`. All map coordinates share the session's identity transform. Build terrain, architecture, props, collision bodies, lights, environment, particles, and map-specific animation beneath that root.

- `build()` constructs map-owned content. It can await frames between expensive stages. Emit `load_progress(message, fraction)` with progress from 0 to 1. Do not create navigation or loading UI.
- `height_at(x,z)` returns the ground height used by the player and camera.
- `walkable(x,z)` identifies safe cat ground. Collision bodies provide building and prop collision.
- `flight_bounds` is an AABB defining horizontal flight limits and minimum/maximum landscape elevation.
- `ambience` is a dictionary consumed by the shared synthesizer: `wind_gain`, `wave_base`, `wave_swell`, `cicada_frequencies` (Vector2), `cicada_gain`, and `birds`. Omitted values are silent; character sounds remain available.
- `supports_surface_traversal` defaults to `false`. Harbor Hills and Daan Gardens opt in to collision-aware gull flight, floor-normal cat alignment, downward surface queries for perching, clearance-checked character switching, and a close obstruction-aware camera. Seabreeze retains its existing terrain-based controller path.
- `set_paused(value)` pauses map-owned audio streams; session processing already pauses simulation. Harbor Hills uses it for its spatial cable-car bell.
- Optional `scenic_views` maps names to `[x,z,height,yaw,pitch]` arrays for inspection. The shared camera adds its scenic eye-height offset.

The base class supplies a flat ground plane's height/walkability contract and silent ambience. A map still owns its visible ground, collision, and environment. Seabreeze Village overrides the ground contract and builds its full procedural landscape. Shared shaders and generator helpers can be reused without making a map depend on another map's scene instance.

## Register another map

1. Create a folder under `maps/` and its scene. Attach a script extending `CozyMap`; implement the terrain queries and `build()` if content is procedural. Authored engine primitives may also be children in the scene. Keep world-specific ambience and behavior here.
2. Create an in-game preview from that scene using only project-owned content. Save it in the map folder or `assets/`.
3. Create a `CozyMapDefinition` resource in the Inspector. Set a unique ID, display metadata, its `.tscn` scene path, preview texture, and a safe spawn. Save it beside the scene.
4. Open `maps/registry.tres` and append that definition to `maps`. The landing screen automatically renders it. No landing, player, camera, or navigation changes are needed.
5. Run the main scene. Verify entry, both characters, pause/settings, return, and repeated re-entry. Inspect the scene with `--map=your_id --profile`; confirm the selector returns to zero live players, cameras, and audio players after unloading.

## Ownership and transitions

The application starts with shared UI and metadata only. Play locks navigation, fades to a loading screen, loads the selected scene resource, and creates one `GameplaySession`. The map builds beneath that session while its processing is disabled. Once construction finishes, the application adds one shared player and camera, applies the registered spawn, reveals the scene, and enables play.

Pause disables processing for the complete session and pauses its audio stream. Collision bodies use `DISABLE_MODE_MAKE_STATIC`, so they remain frozen and available to surface/clearance queries when the paused menu changes characters. Resuming restores their original physics modes. The application and menu remain responsive. Cosmetic shader wind can continue while the simulation is paused. Settings temporarily isolate menu focus and persist in `user://settings.cfg`.

Returning locks navigation and covers the viewport, clears touch input, frees the entire session, waits for scene-tree and physics cleanup, resets the global player-position shader parameter, and restores selector focus. Player, camera, sounds, map nodes, collision, particles, and world post-processing all leave together. No generation thread or timer remains active. The small generator scene is loaded on the main thread, avoiding observed Godot 4.7.2 threaded custom-resource shutdown leaks; expensive map construction still yields and reports progress.

Generated terrain and foliage caches live in `user://` and contain only project-generated resources. They are invalidated by signatures covering the selected map folder, shared components and common shaders. The on-disk cache may remain after unloading; it is not a live map. Do not cache scene-tree instances or player state in the registry.

## Harbor Hills ownership and cache

Harbor Hills registers `maps/harbor_hills/map.tres` with ID `harbor_hills`; its scene root is `world.gd`. `geometry.gd` batches static primitives by material and 40 m cell. `neighborhood.gd` and `nature.gd` construct the district beneath the map root. `transit.gd` owns moving bodies, background gulls and synthesized spatial bell audio. Nothing in this folder creates application UI, a camera or a player.

The static scene is packed into `user://harbor_hills_<signature>.scn`. The shared signature incorporates the map folder, shared components and common shaders, including resource profiles. It contains generated meshes, material resources and collision shapes, never runtime player state. Environment, water, moving fog, post-processing and transit are recreated outside that cache for every visit. Seabreeze keeps its existing separate procedural caches. Returning to selection frees all loaded map instances; cache files alone persist.

No Seabreeze terrain, layout, palette, vegetation or ambience generator changes are part of this integration. Shared additions are opt-in surface traversal, a map-owned audio pause hook, counting spatial audio players in lifecycle diagnostics, and settling the selector scroll position after variable-height cards lay out. The welcome header remains visible on entry; normal focus navigation continues to scroll to each destination.

## Shared construction

All three maps compose the components described in [shared/README.md](shared/README.md). Seabreeze generation has moved out of `scripts/` into `maps/seabreeze_village/`, including its terrain and rice shaders. Map-specific plant meshes, texture recipes, building finishes, distributions and artistic profiles stay there; common gameplay remains centrally owned.

## Daan Gardens ownership and cache

Daan Gardens registers `maps/daan_gardens/map.tres` with ID `daan_gardens`. Its locally owned generators build connected park paths, pond habitat, subtropical planting, furniture and accessible apartment cafés. It composes the shared primitives, leaf painter, batches, collision helpers, atmosphere, particles and cache. The source-aware static scene lives in `user://daan_gardens_<signature>.scn`; dynamic egrets, environment and particles remain outside it. It opts into shared surface traversal without map-ID branches in the controller or changes to the existing maps.
