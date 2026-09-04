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

Pause disables processing for the complete session and pauses its audio stream. The application and menu remain responsive. Cosmetic shader wind can continue while the simulation is paused. Settings temporarily isolate menu focus and persist in `user://settings.cfg`.

Returning locks navigation and covers the viewport, clears touch input, frees the entire session, waits for scene-tree and physics cleanup, resets the global player-position shader parameter, and restores selector focus. Player, camera, sounds, map nodes, collision, particles, and world post-processing all leave together. No generation thread or timer remains active. ResourceLoader's threaded request is awaited before the session becomes playable.

Generated terrain and foliage caches live in `user://` and contain only project-generated resources. They are invalidated by generator script signatures. The on-disk cache may remain after unloading; it is not a live map. Do not cache scene-tree instances or player state in the registry.
