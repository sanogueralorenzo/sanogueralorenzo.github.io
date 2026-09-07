# A Little Further

A local pirate exploration roguelite built with **C#, Godot .NET 4.7.2, and Forward+**. Sail an endless archipelago, follow treasure trails into the hills, ring a pirate shrine, and survive its summons to recruit or develop your crew. Six roles compete for four berths. Death ends the run; the next voyage has a new seed and no inherited rewards.

## Launch

On the development Mac, double-click **Play A Little Further.command**, or run:

```sh
./games/a-little-further/launch.sh
```

The worktree is separate from the website checkout. Run the command from its root, or launch `launch.sh` directly. The script checks the private package, builds C#, and opens the native game. The installed runtime is under `~/.local/share/a-little-further-tools`.

For another installation, provide **Godot .NET 4.7.2**, **.NET SDK 10**, a Forward+ capable GPU, and the owner's private source package:

```sh
export ALF_GODOT=/path/to/Godot_mono
export ALF_DOTNET=/path/to/dotnet
export ALF_SOURCE_VAULT=/path/to/a-little-further-vault
./games/a-little-further/tools/restore-local.sh
./games/a-little-further/launch.sh
```

**The Git checkout intentionally does not contain recovered game code, models, textures, animation curves, or gameplay recordings.** They remain in `Local/` and the owner's source vault. A checkout without that package refuses to build/run instead of silently substituting assets. See [provenance](docs/PROVENANCE.md).

## Controls

| Action | Control |
|---|---|
| Begin / fresh run after death | Enter or click |
| Sail / brake and reverse | W / S |
| Helm | A / D |
| Full sail / toggle cruising | Hold Shift / C |
| Disembark at an amber landing lantern / board | E |
| Walk | WASD or click terrain |
| Jump / glide / climb a steep rise | Space / hold Space |
| Dodge | Tap Shift while moving |
| Rotate the land camera | Q / R |
| Activate a shrine | E nearby |
| Choose a recruit or development | 1 / 2 / 3 or click a card |
| Select the berth to replace when full | R on the choice screen |
| Provision at the landing, for 40 doubloons | F; develops the lowest ranked hand and heals 25 |
| Chart / pause / screenshot | Tab / Escape / F12 |

Captain and crew attack automatically. Movement and dodge timing matter: enemy exclamation marks and ground rings telegraph incoming attacks. Red damage numbers signal a captain hit. Standing among a growing horde is fatal.

## Crew

- **Flint, Gunner:** a timed revolver burst; storm-marked enemies take more damage.
- **Wren, Stormcaller:** chains sparks and marks enemies. Flint killing a marked enemy can trigger a larger lightning burst.
- **Biscuit, Cook:** area bombs and healing from kills.
- **Finch, Duelist:** fast close attacks; executes wounded enemies, helping Biscuit sustain the crew.
- **Reef, Harpooner:** strong single shots; chilled targets take greatly increased damage.
- **Moss, Tidekeeper:** chills nearby enemies, reducing their speed and preparing Reef's shatter attacks.

Choosing an existing role increases its rank. A new role joins an empty berth or replaces the selected hand when all four are occupied. Treasure can provision the crew between islands. The tide grows more dangerous with time and shrines claimed.

## Validation and structure

```sh
./games/a-little-further/launch.sh --check
./games/a-little-further/launch.sh -- --seed=73919
./games/a-little-further/launch.sh -- --seed=1701 --autoplay --evidence=/absolute/local/path
./games/a-little-further/launch.sh -- --seed=1701 --travel-test --evidence=/absolute/local/path
```

The validation pilot uses the same movement/combat commands as play. It is explicitly labeled in the HUD. The travel test starts in a sea lane facing east and sails normally for three minutes. It does not award progress or bypass collision.

- `Core/`: deterministic islands and scenery, movement, combat, crew choices, run state, and origin shifting; no Godot dependency.
- `Runtime/`: Godot input, geometry/material loading, camera, sound, UI, rendering, and a validation driver.
- `Local/`: private engine-independent source translations and extracted runtime assets; ignored by Git and the Godot importer.
- `tests/`: standalone .NET checks across seeds, shrine traversal, combat, replacement, death, and extended travel.

[Validation evidence and hardware](docs/VALIDATION.md) · [Source recovery and limitations](docs/PROVENANCE.md) · [Architecture](docs/ARCHITECTURE.md)

The repository's MIT license covers the authored redistributable project files. It does not grant rights to any recovered material or to the source games.
