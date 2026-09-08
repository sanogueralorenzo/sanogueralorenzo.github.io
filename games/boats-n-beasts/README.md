# Boats n Beasts

An original procedural 2D sailing roguelike for Godot .NET. Sail an endless seeded ocean, fight with automatic weapons, fish for refit money, and bring a completed chart home after defeating the Crownclaw.

## Run

Install the .NET 10 SDK and Godot **4.7.2 .NET** (the standard non-.NET editor cannot run this project). From this directory:

```sh
./run.command
```

The launcher builds C#, imports the project, and opens the game with the Compatibility renderer. Set `GODOT_BIN` to the Godot executable if it is not at the macOS locations searched by the launcher; set `DOTNET_ROOT` if your SDK is elsewhere. Alternatively build `BoatsNBeasts.csproj`, then open `project.godot` in the matching .NET editor and run the main scene.

There are no external visual assets, imported fonts, audio assets, or automated tests. Art is original geometry and shaders. Creature animation strips and bounded scenery caches are rendered from that geometry in the engine and live only in memory.

## Play

The home menu starts with **Play**, which opens boat selection. **Unlock**, **Quests**, and **Shop** appear after 1, 2, and 3 ended voyages. They are placeholders with no action yet. Defeat, victory, or returning to the menu ends a voyage and counts it once; continuing after victory does not count twice. Existing saves start this counter from their recorded wins. Settings and the handbook remain available from pause.

- **WASD / arrows:** sail. **Left click:** sail to a point and stop. **Right click:** toggle continuous mouse helm.
- **Space / Shift:** boost while moving. Boost reduces damage; releasing an exhausted boost lets it recharge. Settings offers a tap-to-toggle alternative.
- **E:** fish near a school or dock inside a harbor's dashed safety boundary.
- **Space / E while fishing:** reel inside the turquoise band. Three hits land the catch; three misses or 16 seconds lose it. Each school allows one cast. Success, failure, or Escape cancellation uses it up. Assisted fishing is an optional setting that times reels for you.
- **Escape:** pause, cancel fishing, or leave a result/harbor screen. **Enter / Tab / arrows:** operate menus. Space cannot accidentally select an upgrade while boosting.
- **×1 / ×2 / ×3, below the top-left counters:** cycle game speed. Sailing, combat, fishing and effects advance faster; pauses still freeze the voyage. Each new voyage starts at ×1.
- **F11:** fullscreen. **F12:** save a native viewport image and runtime measurements under `evidence/`.

Catch fish at three different schools beyond one league. After completing the chart, sail beyond three leagues to summon the Crownclaw. Its defeat disperses the escort and gives you a calm return to any harbor. Claim victory there, then choose a fresh voyage or resume combat in endless exploration.

Sell catches for gold, repair, and buy weapons or stat upgrades at harbors. Combat levels offer three varying free upgrades. There are no prerequisite trees or permanent stat grind. Silver becomes eligible after a fresh random 45–90 seconds of combat time and is awarded on the next kill. Each award starts a new random interval; saved silver is retained and idle time cannot bank extra drops; silver spending is reserved for a future update. A new voyage resets catches, money, and equipment; silver, settings, best kill count, and completed-voyage count persist locally. The horizontal top-left counters use code-drawn clock, silver coin, gold coin and skull icons for combat time (scaled by game speed and frozen during fishing/pauses), saved silver, current-run gold, and kills.

Experience fills the thin bar along the top edge. The small red bar above your boat shows its remaining hull. Acquired weapons and stat upgrades appear with their ranks in a centered bottom row; empty slots are hidden. Pause to review the current voyage objective.

## Boats and builds

| Boat | Base ability | Starting weapons |
| --- | --- | --- |
| Cutter | Boost grants +65% fire rate, lasting 1.25 seconds after release. Faster movement, lighter hull. | Cannon + Blast |
| Trawler | Slow movement charges a pulse that clears nearby shots and soaks enemies; takes 30% less damage at low speed. | Cannon + Whirlpool |

Every boat can use all six weapons:

| Weapon | What it does |
| --- | --- |
| Cannon | Fast aimed shots. Level 3 adds a second barrel. |
| Harpoon | Pierces a line of enemies, slowing and soaking them. |
| Bomb | Long-range blasts for crowds. |
| Lightning | Jumps between enemies. Each level adds a target. |
| Whirlpool | Damages enemies all around the boat. |
| Blast | A close-range burst that pushes enemies back. |

Soaked enemies take **+50% damage from Bomb, Lightning and Blast**. Each weapon level also improves damage and fire rate. Upgrade cards show the next level’s benefit.

Four boat upgrades keep choices simple: **Hull** (+25 health and heal 25), **Speed** (+10% sailing speed), **Reload** (+12% fire rate), and **Reach** (+15% attack size/chain reach). Harbor swaps retain equipment and hull percentage.

## Structure

- `source/core/OceanWorld.cs`: seed-and-coordinate geography, collision, bounded 5×5 chunk streaming, sparse discovery/depletion history.
- `source/core/SpawnDirector.cs`: original distance-based credit and population tuning, encounter lulls, boss escort ceiling.
- `source/core/Voyage.cs`: engine-independent movement, combat, fishing, economy, progression and endings.
- `source/presentation/Game.cs`: input, menus, HUD, local settings and manual review captures.
- `source/presentation/OceanView.cs`, `ProceduralArt.cs`, `CreatureAtlas.cs`, `SceneryCache.cs`, `ocean.gdshader`: original rendering, animation, water and effects.

World generation has independent coordinate-local randomness; combat, upgrade offers, and fishing use separate streams. Each school is consumed when casting starts, so cancelling cannot retry or reroll it. Fishing and results stop all combat updates. Distant chunks unload; school depletion survives their return. Sparse exploration history grows with visited places, while active chunks and visual caches are bounded.

See `docs/OBJECTIVE.md` for scope, `docs/QUALITY.md` for current validation and remaining gaps, and `docs/RESEARCH.md` for research provenance. No simulation harness or automated test results stand in for actual play.

The top-right corner contains only LVL and a north-up nautical chart. Islands use shoreline outlines, harbors use anchors, fish use wave marks, and the center arrow follows your heading. A rim anchor points home when distant. Voyage objectives remain in pause and cargo totals are available when fishing or docking.
