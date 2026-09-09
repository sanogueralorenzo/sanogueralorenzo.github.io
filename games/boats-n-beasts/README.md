# Boats ’n’ Beasts

A procedural 3D sailing roguelike for Godot .NET. Explore a seeded ocean, upgrade automatic weapons, and survive until Crownclaw arrives at 22 minutes.

## Run

Requires .NET 10 SDK and Godot **4.7.2 .NET** with Forward+. From this directory:

```sh
./run.command
```

Set `GODOT_BIN` to your Godot executable and `DOTNET_ROOT` to your SDK directory if the launcher cannot find them. Alternatively, build `BoatsNBeasts.csproj` and run `project.godot` in the matching .NET editor.

## Play

| Input | Action |
| --- | --- |
| WASD / arrows | Sail |
| Left click | Sail to a point |
| Space / Shift | Boost; release after exhaustion to recharge |
| E | Fish or open a nearby harbor |
| Space / E while fishing | Reel inside the turquoise band |
| Escape | Pause, cancel fishing, or leave a menu |
| Enter / Tab / arrows | Operate menus |
| ×1 / ×2 / ×3 button | Change voyage speed |
| F12 | Save native screenshot and telemetry to `evidence/` |

Choose Gunboat (Cannon, faster fire during boost), Aura (Whirlpool, periodic defensive pulse), or Mage (homing Arcane Orbs). Boat choice lasts the voyage. All boats can equip any weapon, with **two total weapon slots**, including the starter.

Level-ups pause combat for a free upgrade. Each harbor sells repairs and three fixed weapon or boat upgrades. Press E near its dock to open the menu and sell catches; combat pauses while the menu is open.

Each fishing school allows one cast, including cancellation. Reel inside the band within eight seconds. Fishing stops the boat and new automatic attacks; enemies, existing shots and voyage time keep moving.

Monster numbers and variety increase gradually with active voyage time. Swimming speeds, health and damage do not scale with time or distance. Puffers chase, fuse and explode; only Crownclaw fires hostile projectiles. Defeat Crownclaw to win, then restart or keep exploring. Distance improves rewards, not combat difficulty.

Rare beach chests award 35–55 gold and are collected from the water. Sparse floating barrels break on hull contact for 3–6 gold. Home has no guaranteed loot. Pickups and fishing schools remain depleted on revisits. Gold, equipment and catches reset each voyage; silver and records persist. Silver spending and the Unlock/Quests/Shop menu entries are not implemented.

## Development

- Keep simulation in plain C# under `source/core`; presentation reads it without changing gameplay state.
- Generate gameplay art with C#, Godot geometry and shaders. No external/image-generated gameplay assets, GDScript or audio.
- Follow the build and native-play checks in [QUALITY.md](docs/QUALITY.md).
- Keep documentation about current behavior; use Git history for completed work and superseded decisions.

| Owner | Responsibility |
| --- | --- |
| `StartingArea.cs` | Shared title and voyage geography |
| `OceanWorld.cs`, `IslandShape.cs` | Deterministic placement, coastline, collision and streaming |
| `SpawnDirector.cs` | Population, species introductions and boss timing |
| `Voyage*.cs` | Movement, combat, fishing, rewards and progression |
| `Game.cs` | Input, menus, HUD, saves and captures |
| `NativeStage3D.cs`, `OceanView3D.cs` | Camera, coordinate conversion and bounded scene resources |
| Remaining presentation classes and shaders | Procedural actors, scenery and effects |

Geography depends only on seed and coordinates, independently of travel order. Keep depletion outside chunk data, randomness separate by subsystem, placement attempts bounded, and active streaming at 5×5 chunks. Preserve neighbor clearance when changing island sizes.

See [art direction](docs/ART_DIRECTION.md) and [verification, evidence and provenance](docs/QUALITY.md).
