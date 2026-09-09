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
| Escape | Pause or resume |
| Enter / Tab / arrows | Operate menus |
| ×1 / ×2 / ×3 button | Change voyage speed |
| F12 | Save native screenshot and telemetry to `evidence/` |

Choose Gunboat (Cannon, faster fire during boost), Aura (Whirlpool, periodic defensive pulse), or Mage (homing Arcane Orbs). Boat choice lasts the voyage. All boats can equip any weapon, with **two total weapon slots**, including the starter.

Level-ups pause combat for a free weapon or boat upgrade. Each level offers up to three stacked choices from a single category: weapons or boat upgrades. Categories alternate, starting with weapons; if a category is maxed, the other is offered. Each choice has an icon beside its description; click the row or select it with the keyboard. Once every available upgrade is maxed, each level offers 25 health instead.

The only harbor is the larger starting island. It is decorative: no docking, shops, repairs, or interaction. There is no fishing or voyage gold economy.

Monster numbers and variety increase gradually with active voyage time. Swimming speeds, health and damage do not scale with time or distance. Puffers chase, fuse and explode; only Crownclaw fires hostile projectiles. Defeat Crownclaw to win, then restart or keep exploring. Distance does not scale rewards or combat difficulty.

Rare beach chests award 12 XP and are collected from the water. Sparse floating barrels marked with a turquoise health cross restore up to 25 health on hull contact. Barrels remain available at full health. Home has no guaranteed loot. Pickups remain depleted on revisits. Equipment resets each voyage; silver and records persist. Silver spending and the Unlock/Quests/Shop menu entries are not implemented.

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
