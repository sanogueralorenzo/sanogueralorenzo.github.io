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

Sell catches for gold and repair at harbors. Each harbor stocks three fixed offers from one category: weapons or boat upgrades. Revisiting does not reroll stock. Runs have two total weapon slots, including the starting weapon; equipped weapons can still be upgraded when slots are full. Both paid and free upgrades respect the limit. Future between-run shop upgrades can add one slot at a time, up to five; spending remains unimplemented. Combat levels offer three varying free upgrades. There are no prerequisite trees or permanent stat grind. Silver becomes eligible after a fresh random 45–90 seconds of combat time and is awarded on the next kill. Each award starts a new random interval; saved silver is retained and idle time cannot bank extra drops; silver spending is reserved for a future update. A new voyage resets catches, money, and equipment; silver, settings, best kill count, and completed-voyage count persist locally. The horizontal top-left counters use code-drawn clock, silver coin, gold coin and skull icons for combat time (scaled by game speed and frozen during fishing/pauses), saved silver, current-run gold, and kills.

Experience fills the thin bar along the top edge. The small red bar above your boat shows its remaining hull. Acquired weapons and stat upgrades appear as procedural icons with rank badges in a centered bottom row; hover for names and descriptions. Empty slots are hidden. A small turquoise arc below the boat shows boost charge while boosting or recharging; coral means exhausted, with a release/toggle cue. Bulwark explains itself once per save, then uses its short pulse effect. Monsters emerge through a brief ripple before moving or attacking. Chart harbors carry a cannon or hull symbol; hovering a discovered harbor, or sailing near one, previews its three fixed offers, prices and capacity/max-rank restrictions. Pause to review the current voyage objective.

## Boats and builds

| Boat | Base ability | Starting weapons |
| --- | --- | --- |
| Cutter | Boost grants +65% fire rate, lasting 1.25 seconds after release. Faster movement, lighter hull. | Broadside |
| Trawler | Slow movement charges a pulse that clears nearby shots and soaks enemies; takes 30% less damage at low speed. | Whirlpool |

Every boat can use all six weapons:

| Weapon | What it does |
| --- | --- |
| Cannon | Auto-aimed cannonballs ricochet between enemies and off rocks. Level 3 adds a second barrel. |
| Harpoon | Pierces, pulls and soaks enemies. Bosses resist most of the pull. |
| Mines | Drops a mine behind the moving boat. Arms after 0.5 seconds; bursts when an enemy approaches. |
| Lightning | Jumps between enemies. Each level adds a target. |
| Whirlpool | Damages enemies all around the boat. |
| Broadside | Three cannons on each side fire automatically at foes alongside the boat. |

Soaked enemies take **+50% damage from Mines, Lightning and Broadside**. Each weapon level also improves damage and fire rate. Upgrade cards show the next level’s benefit.

Four boat upgrades keep choices simple: **Hull** (+25 max health), **Speed** (+10% sailing speed), **Reload** (+12% fire rate), and **Reach** (+15% attack area). Hull upgrades leave current health unchanged; repairs are a separate harbor action. Harbor swaps retain equipment and hull percentage.

## Structure

- `source/core/OceanWorld.cs`: seed-and-coordinate geography, collision, bounded 5×5 chunk streaming, sparse discovery/depletion history.
- `source/core/SpawnDirector.cs`: original distance-based credit and population tuning, encounter lulls, boss escort ceiling.
- `source/core/Voyage.cs`: engine-independent movement, combat, fishing, economy, progression and endings.
- `source/presentation/Game.cs`: input, menus, HUD, local settings and manual review captures.
- `source/presentation/OceanView.cs`, `ProceduralArt.cs`, `CreatureAtlas.cs`, `SceneryCache.cs`, `ocean.gdshader`: original rendering, animation, water and effects.

World generation has independent coordinate-local randomness; combat, upgrade offers, and fishing use separate streams. Each school is consumed when casting starts, so cancelling cannot retry or reroll it. Fishing and results stop all combat updates. Distant chunks unload; school depletion survives their return. Sparse exploration history grows with visited places, while active chunks and visual caches are bounded.

See `docs/OBJECTIVE.md` for scope, `docs/QUALITY.md` for current validation and remaining gaps, and `docs/RESEARCH.md` for research provenance. No simulation harness or automated test results stand in for actual play.

LVL is aligned to the far top-right edge, separate from the north-up nautical chart below. Islands use shoreline outlines, harbors use anchors, fish use wave marks, and the center arrow follows your heading. A rim anchor points home when distant. Voyage objectives remain in pause and cargo totals are available when fishing or docking.

Boat selection contains only the boat choice, Set Sail and Back. Every new run, including retry, generates a fresh ocean automatically; seeds are internal diagnostics only.

Menus use compact navy panels, cream text, turquoise selection and gold purchase controls. Harbor and level-up offers share three equal cards with original code-drawn symbols and concise benefits. Hover motion and purchase pulses respect Reduced motion.

The gameplay art follows the approved nautical concept using original code-drawn shapes: muted petrol-blue water, sparse waves, turquoise wakes and shallows, warm sand and broad rocks, cream cabins over wood decks, coral crabs, ochre puffers and teal serpents/rays. Fishing spots use layered turquoise ripples and three cream fish. Geometry remains lightweight and the existing creature/scenery caches are retained.

The gameplay camera uses 0.74× zoom (about 35% more horizontal ocean) and 0.84 vertical foreshortening for a subtle tilted 2D view. World art, shader, culling, click destinations and mouse steering share the projection; menus and HUD retain their screen scale. Islands use curved coves, raised rocky banks and scattered shore stones. Fishing ripples are broken, irregular arcs around three moving fish.

## Sailing encounters

The bow turns responsively while the hull keeps a short drift. Boost gives an immediate kick and reaches 2.05× normal speed, with a brighter, wider wake; each new burst costs 8 boost plus the usual drain. Releasing steering slows the boat quickly. Turquoise current arrows show the direction of flow, adding up to 125 world units/second per lane (150 total cap). Steering against a current remains possible.

Sail over floating treasure for 12–20 run gold, or salvage wrecks between rocks for 35–55 gold. Both are collected automatically once per location per run, disappear from the chart after collection, and remain depleted when chunks reload. The home waters include one of each encounter; farther discoveries vary by seed. Encounters do not award silver.

Mines last up to 10 seconds and are limited to eight active mines. Harpoons pull surviving targets over 0.4 seconds, slowing and soaking them; a rope briefly shows the pull. Cannonballs start with one bounce and gain another at ranks 2 and 4. Broadside automatically aims within the port/starboard arcs, so turning alongside foes matters without manual aiming.
