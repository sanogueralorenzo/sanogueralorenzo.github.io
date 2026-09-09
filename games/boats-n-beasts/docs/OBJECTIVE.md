# Boats n Beasts

Historical objective. The selected Direction B objective supersedes the 2D/Compatibility and older feature directions below; see [ART_DIRECTION.md](ART_DIRECTION.md), [README.md](../README.md) and the current section of [QUALITY.md](QUALITY.md). The prohibition on automated tests still applies.

Finish a polished desktop 2D boat roguelike in `games/boats-n-beasts`, working exclusively in the existing worktree at `/Users/mario/AndroidStudioProjects/boats-n-beasts-worktree`. Preserve the gameplay scope below; freely revise implementation and content when that improves the game.

## Requirements

- Use Godot .NET, C#, and the Compatibility renderer. Keep generation, combat, spawning, difficulty, and economy in plain C# with minimal engine dependencies and simple ownership.
- Deliver responsive sailing, dodging and boost; automatic mounted-weapon combat with meaningful combinations; fishing; safe harbors for selling catches, repairs and upgrades; and defeat/restart. Prioritize replayable runs and build synergies that change how the boat plays.
- Provide varied enemies with distinct behaviors and at least two boats with distinct base abilities and playstyles. Make future boats straightforward to add. Choose original species, silhouettes, abilities and combinations for gameplay value; existing content is provisional.
- Stream a seeded, infinite ocean with navigable geography. Seed and coordinates must determine geography independently of exploration order. Unload distant chunks and preserve changes on revisits, including depleted fishing spots. Distance increases danger and reward.
- Fishing freezes monsters, projectiles and all combat timers; leaving fishing resumes them consistently.
- Choose a coherent run structure, victory condition, progression, fishing controls and boat switching. Finish menus, controls, pause, settings, UI, animation and effects.

## Latest progression direction

The 2026-09-09 pacing request supersedes distance-based combat difficulty: aim for a 20–25 minute voyage, bring Crownclaw at 22 minutes of active voyage time, grow enemy numbers gradually, and keep enemy swimming speeds fixed. Enemy health and damage stay fixed too; distance continues to affect rewards. See the current pacing table in [README.md](../README.md).

Keep upgrades simple, like Megabonk: small varying level-up choices of weapon ranks and plainly explained stat/passive upgrades, a few obvious synergies, and distinct boat base abilities. Every boat must support ranged weapons, damaging aura weapons and short-range automatic attacks, with a viable ranged weapon from the start. No prerequisite trees, specialization graphs, catch equipment, or extra progression currencies. Nova Drift informs readability and satisfying combat, not progression complexity.

## Art and verification

Generate every visual through original C#, Godot shaders, procedural geometry, generated textures, particles or engine primitives. No external or imagegen assets. Audio is out of scope: remove its implementation and assets.

Use the reference only for bright, shaded dimensional 2D presentation, a near-overhead ocean view, spacious composition and readable UI. Its creatures, boats, colors and structures are inspiration, not a required roster or exact template:
`/Users/mario/.codex/generated_images/01a07e06-5832-7060-881b-c05f322aeb58/exec-bfd666ab-9a88-4b19-8df6-6e87fc905847.png`

Do not create automated tests. Verify with builds, actual runtime play, UI interaction, native screenshots, visual comparison and sustained gameplay, including crowded combat and long exploration. Maintain and resolve a concrete quality-gap list. Prioritize excellent execution over content quantity. Continue until polished and fully playable, then commit. Report any external blocker and unfinished work accurately.

## Research inputs

Adapt useful generation, placement and streaming ideas from `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/games/sno-godot-local/`, starting with `scripts/main.gd` and `source/runtime/{TerrainCore,ObstaclePlacementCore,PopulationCore}.cs`.

Verify Megabonk spawning and monster-count progression before adapting useful ideas to distance. Distinguish recovered behavior from custom tuning; neither dictates our roster or balance. Sources:
- Installation: `/Users/mario/Applications/Sikarugir/Windows Steam.app/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Megabonk/`
- Extracted material: `/Users/mario/GameSourceVault/a-little-further/megabonk/`
- Metadata: `/Users/mario/GameSourceVault/a-little-further/dumper/dump.cs`
