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

- **WASD / arrows:** sail. **Left click:** sail to a point and stop. **Right click:** toggle continuous mouse helm.
- **Space / Shift:** boost while moving. Boost reduces damage; releasing an exhausted boost lets it recharge. Settings offers a tap-to-toggle alternative.
- **E:** fish near a school or dock inside a harbor's dashed safety boundary.
- **Space / E while fishing:** reel inside the turquoise band. Three hits land the catch; three misses or 16 seconds lose it. Escape cancels. Assisted fishing is an optional setting that times reels for you.
- **Escape:** pause, cancel fishing, or leave a result/harbor screen. **Enter / Tab / arrows:** operate menus. Space cannot accidentally select an upgrade while boosting.
- **×1 / ×2 / ×3, top right:** cycle game speed. Sailing, combat, fishing and effects advance faster; pauses still freeze the voyage. Each new voyage starts at ×1.
- **F11:** fullscreen. **F12:** save a native viewport image and runtime measurements under `evidence/`.

Catch fish at three different schools beyond one league. After completing the chart, sail beyond three leagues to summon the Crownclaw. Its defeat disperses the escort and gives you a calm return to any harbor. Claim victory there, then choose a fresh voyage or resume combat in endless exploration.

Sell catches for coins, repair, and buy weapons or stat upgrades at harbors. Combat levels offer three varying free upgrades. There are no prerequisite trees or permanent stat grind. A new voyage resets catches, money, and equipment; settings, best kill count, and completed-voyage count persist locally.

Experience fills the thin bar along the top edge. The small red bar above your boat shows its remaining hull.

## Boats and builds

| Boat | Base ability | Starting weapons |
| --- | --- | --- |
| Cutter | Boost grants +65% fire rate, lasting 1.25 seconds after release. Faster movement, lighter hull. | Cannon + scatter broadside |
| Trawler | Slow movement charges a pulse that clears nearby shots and soaks enemies; takes 30% less damage at low speed. | Cannon + undertow aura |

Every boat can use ranged cannon/harpoon/mortar, chain lightning, a damaging aura, and a short-range scatter attack. Harpoons slow and soak enemies; soaked targets amplify mortar, coil, and scatter damage. Cannon rank 3 adds a second barrel. Other weapon ranks improve damage, cadence, reach or chain count. Hull, engine, reload, and area upgrades support simple combinations. Harbor boat swaps retain equipment and hull percentage.

## Structure

- `source/core/OceanWorld.cs`: seed-and-coordinate geography, collision, bounded 5×5 chunk streaming, sparse discovery/depletion history.
- `source/core/SpawnDirector.cs`: original distance-based credit and population tuning, encounter lulls, boss escort ceiling.
- `source/core/Voyage.cs`: engine-independent movement, combat, fishing, economy, progression and endings.
- `source/presentation/Game.cs`: input, menus, HUD, local settings and manual review captures.
- `source/presentation/OceanView.cs`, `ProceduralArt.cs`, `CreatureAtlas.cs`, `SceneryCache.cs`, `ocean.gdshader`: original rendering, animation, water and effects.

World generation has independent coordinate-local randomness; combat, upgrade offers, and fishing use separate streams. Cast randomness is tied to the school and depletion count so cancellation cannot reroll its reward. Fishing and results stop all combat updates. Distant chunks unload; school depletion survives their return. Sparse exploration history grows with visited places, while active chunks and visual caches are bounded.

See `docs/OBJECTIVE.md` for scope, `docs/QUALITY.md` for current validation and remaining gaps, and `docs/RESEARCH.md` for research provenance. No simulation harness or automated test results stand in for actual play.
