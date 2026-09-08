# Runtime boundaries

The C# core owns the run. `Run.Tick` takes a small movement/action command and advances a fixed-step simulation. Godot reads its state and hit events; it does not decide rewards, enemy damage, crew ranks, shrine completion, or procedural island layout. `CombatTuning` is plain data loaded by a narrow JSON adapter.

`World` maps signed cell coordinates to deterministic islands. `IslandLayout` generates branching routes, scenery, obstacle circles, meadow patches, and treasure positions. `TerrainMeshData` builds indexed terrain, edge-sampled normals, route distances, and placement data on a background task using only System.Numerics. The renderer uploads these arrays into Godot meshes. This is a height-field traversal game, rather than a rigid-body simulation of every prop.

The private `PrivateSources` C# file is also engine independent. It contains the local source translations. Moving the core to Unity requires supplying that local file and the same tuning, then replacing the adapters. No parallel engine interfaces, service containers, or Unity dependencies were added.

## Bounded rendering and coordinates

A radius of one placement cell retains at most **9 island render roots**. Cells are **3,200 metres** wide, with deterministic per-island offsets. The core’s first-sighting boundary is 620 metres plus island radius; the camera/fog agree with that range. The map hides undiscovered islands beyond it. Detail is prepared within 880 metres, before it enters view.

One CPU generation task runs at a time. Completed work is discarded if its cell has left the desired neighbourhood. Queues are nearest-first and deduplicated. The renderer upgrades distant meshes on approach and frees roots outside the neighbourhood. The close terrain is an indexed 161×161 grid; distant terrain uses 25×25. Source trees are batched by four mesh variants and shrubs by three; leaf cards fade to crown silhouettes at distance. A narrow camera-to-subject clearance keeps foreground foliage from hiding the captain. Grass is divided into 24-metre batches with an 85-metre visibility range. The original boat’s static geometry is consolidated into 18 material groups.

The core rebases positions beyond 2,400 metres, snapping the origin to placement cells. Integer origin cells retain island identity. Ship, captain, enemies, render roots, wake knots, camera, effects, and diagnostic pilot waypoints shift together. Wave origins are accumulated as doubles and reduced to per-component phase offsets for GPU uniforms. Generation uses island-local coordinates, so terrain does not change across a rebase. Coast-derived landings remain above water across outline variations.

Visited/claimed/treasure identities are retained for the current run so returning to an island cannot farm the same reward. These small sets grow with exploration; rendered world geometry, enemy count, effects, and wake history remain bounded. There is no disk-backed run state. The chart pauses simulation and closes directly with Escape.

## Combat and feedback

Nearest eligible targets are selected automatically through the private Megabonk-derived no-vision scan. Crew attacks have role-specific cooldowns; Flint additionally emits a timed burst. Status effects, execute thresholds, chained marks, chilling, and triggered lightning interact within a four-hand roster. Enemies telegraph attacks before resolving their range/damage. Dodging provides a short invulnerability window. Visual tracers, particles, damage numbers, camera response, and audio respond to core hit events.

Threat accumulates during exploration and from claimed shrines; open-water travel does not make the next landing unfairly harder. Each island has eight trail pickups and four larger optional caches, a 24-second bell encounter, and a provisioning point at the landing.

The core caps active enemies at 72. Effects cap particles, tracers, and damage labels at 220 combined and wake history is limited to 24 knots. Private recovered tuning is adapted explicitly at the loader, keeping source values separate from this game's balance multipliers.

## No persistence

A dead run stops advancing. Restart constructs a new core and render world, clears encounters/rewards, and chooses a fresh seed. Screenshots and validation metrics are diagnostic artifacts only; frame samples are collected only with an evidence directory and capped at 60,000; they are never loaded as game state.

## Capture diagnostics

Screenshots read the viewport on the main thread after rendering. PNG encoding uses a background task with exclusive ownership of its CPU Image; it does not touch the active scene or GPU there. Shutdown waits for pending writes, and repeated automatic captures of the same event are deduplicated. This follows Godot’s [resource/thread ownership guidance](https://docs.godotengine.org/en/latest/tutorials/performance/thread_safe_apis.html). Capture files and metrics are never used to restore a run.
