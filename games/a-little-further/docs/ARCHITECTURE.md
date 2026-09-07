# Runtime boundaries

The C# core owns the run. `Run.Tick` takes a small movement/action command and advances a fixed-step simulation. Godot reads its state and hit events; it does not decide rewards, enemy damage, crew ranks, shrine completion, or procedural island layout. `CombatTuning` is plain data loaded by a narrow JSON adapter.

`World` maps signed cell coordinates to deterministic islands. `IslandLayout` generates scenery, obstacle circles, and treasure positions. Terrain height queries and bordered mesh samples are engine independent. The renderer turns those samples into Godot meshes. This is a height-field traversal game, rather than a rigid-body simulation of every prop.

The private `PrivateSources` C# file is also engine independent. It contains the local source translations. Moving the core to Unity requires supplying that local file and the same tuning, then replacing the adapters. No parallel engine interfaces, service containers, or Unity dependencies were added.

## Bounded rendering and coordinates

A radius of two cells retains at most **25 island render roots**. Cells are 192 metres wide. The renderer processes one queued cell per frame, with detailed meshes/scenery nearby and coarser terrain at distance. Detailed cells are upgraded on approach. Roots outside the active neighbourhood are freed; GPU meshes and extracted asset meshes are reused where practical. The original boat's static geometry is consolidated into 18 material groups.

The core rebases positions when the captain/boat passes 768 metres from the local origin. An integer origin cell retains global identity. Ship, captain, enemies, render roots, wake knots, camera, and effects shift together. Wave origins are accumulated as doubles and reduced to per-component phase offsets for GPU uniforms. Island generation samples island-local coordinates, so terrain does not change across a rebase.

Visited/claimed/treasure identities are retained for the current run so returning to an island cannot farm the same reward. These small sets grow with exploration; rendered world geometry, enemy count, effects, and wake history remain bounded. There is no disk-backed run state.

## Combat and feedback

Nearest eligible targets are selected automatically through the private Megabonk-derived no-vision scan. Crew attacks have role-specific cooldowns; Flint additionally emits a timed burst. Status effects, execute thresholds, chained marks, chilling, and triggered lightning interact within a four-hand roster. Enemies telegraph attacks before resolving their range/damage. Dodging provides a short invulnerability window. Visual tracers, particles, damage numbers, camera response, and audio respond to core hit events.

The core caps active enemies at 72. Effects cap particles, tracers, and damage labels at 220 combined and wake history is limited to 24 knots. Private recovered tuning is adapted explicitly at the loader, keeping source values separate from this game's balance multipliers.

## No persistence

A dead run stops advancing. Restart constructs a new core and render world, clears encounters/rewards, and chooses a fresh seed. Screenshots and validation metrics are diagnostic artifacts only; frame samples are collected only with an evidence directory and capped at 60,000; they are never loaded as game state.
