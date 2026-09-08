# Boats ’n’ Beasts

An original procedural 3D sailing roguelike for Godot .NET. Sail an endless seeded ocean, fight with automatic weapons, fish for refit money, and defeat the Crownclaw beyond three leagues.

## Run

Install the .NET 10 SDK and Godot **4.7.2 .NET** (the standard non-.NET editor cannot run this project). From this directory:

```sh
./run.command
```

The launcher builds C#, imports the project, and opens the game with the Forward+ renderer. Set `GODOT_BIN` to the Godot executable if it is not at the macOS locations searched by the launcher; set `DOTNET_ROOT` if your SDK is elsewhere. Alternatively build `BoatsNBeasts.csproj`, then open `project.godot` in the matching .NET editor and run the main scene.

There are no external visual assets, imported fonts, audio assets, or automated tests. Art is original geometry and shaders. Merged native meshes, shared matte materials, bounded scenery and actor caches, procedural water and position-history effects are generated in memory.

## Play

The home menu starts with **Play**, which opens boat selection. **Unlock**, **Quests**, and **Shop** appear after 1, 2, and 3 ended voyages. They are placeholders with no action yet. Defeat, victory, or returning to the menu ends a voyage and counts it once; continuing after victory does not count twice. Existing saves start this counter from their recorded wins. The handbook remains available from pause.

- **WASD / arrows:** sail. **Left click:** sail to a point and stop.
- **Space / Shift:** boost while moving. Releasing an exhausted boost lets it recharge.
- **E:** fish near a school or open the harbor upgrade menu near a dock. Combat pauses only while that menu is open; the surrounding water offers no protection.
- **Space / E while fishing:** reel inside the turquoise band. One successful reel lands the catch; one miss or 8 seconds without reeling loses it. The fish name and gold value appear briefly above the boat; sailing resumes immediately without a result menu. Each school allows one cast. Success, failure, or Escape cancellation uses it up.
- **Escape:** pause, cancel fishing, or leave a result/harbor screen. **Enter / Tab / arrows:** operate menus. Space cannot accidentally select an upgrade while boosting.
- **×1 / ×2 / ×3, below the top-left counters:** cycle game speed. Sailing, combat, fishing and effects advance faster; pauses still freeze the voyage. Each new voyage starts at ×1.
- **F12:** save a native viewport image and runtime measurements under `evidence/`.

Sail beyond three leagues to summon the Crownclaw. Defeat it to win immediately, then start a fresh voyage or keep exploring. Fishing is optional income for upgrades and repairs.

Keep as many catches as you find; there is no storage limit or cargo counter. Catches automatically sell for gold when you press E to open the harbor menu. Repair and buy upgrades at harbors. Each harbor stocks three fixed offers from one category: weapons or boat upgrades. Revisiting does not reroll stock. Runs have two total weapon slots, including the starting weapon; equipped weapons can still be upgraded when slots are full. Both paid and free upgrades respect the limit. Leveling up pauses combat and offers up to three free upgrades; during fishing, choices wait until the cast ends. Choose one to resume sailing in place; no harbor visit is needed. If several levels arrive together, resolve one choice per level before resuming. There are no prerequisite trees or permanent stat grind. Silver becomes eligible after a fresh random 45–90 seconds of combat time and is awarded on the next kill. Each award starts a new random interval; saved silver is retained and idle time cannot bank extra drops; silver spending is reserved for a future update. A new voyage resets catches, money, and equipment; silver, best kill count, and completed-voyage count persist locally. The horizontal top-left counters use code-drawn clock, silver coin, gold coin and skull icons for combat time (scaled by game speed and frozen during pauses), saved silver, current-run gold, and kills.

Experience fills the thin bar along the top edge. The small red bar above your boat shows its remaining hull. Acquired weapons and stat upgrades appear as procedural icons with rank badges in a centered bottom row; hover for names and descriptions. Empty slots are hidden. A small turquoise arc below the boat shows boost charge while boosting or recharging; coral means exhausted, with a release cue. Bulwark explains itself once per save, then uses its short pulse effect. Monsters emerge through a brief ripple before moving or attacking. Spiky puffers chase you, stop and swell for about a second, then explode in a red dome; sail clear or destroy them before they burst. They never shoot, and self-detonations do not award kills or loot. Violet swift variants of regular monsters move 50% faster; one in four spawns is swift. Chart harbors carry a cannon or hull symbol; hovering a discovered harbor, or sailing near one, previews its three fixed offers, prices and capacity/max-rank restrictions. Pause to review the current voyage objective.

## Boats and builds

| Boat | Base ability | Starting weapons |
| --- | --- | --- |
| Gunboat | Fires 65% faster while boosting. Faster movement, lighter hull. | Cannon |
| Aura | Every 6 seconds, a pulse clears nearby shots and pushes enemies away. | Whirlpool |
| Mage | Homing magic follows enemies without lining up a shot. | Arcane Orbs |

Every boat can use all six weapons:

| Weapon | What it does |
| --- | --- |
| Cannon | Auto-aimed cannonballs ricochet between enemies and off rocks. Each upgrade adds another cannonball per shot. |
| Harpoon | Pierces enemies and pulls them closer. Bosses resist most of the pull. |
| Mines | Drops a mine behind the moving boat. Arms after 0.5 seconds; bursts when an enemy approaches. |
| Lightning | Jumps between enemies. Each level adds a target. |
| Whirlpool | Damages enemies all around the boat. |
| Arcane Orbs | Violet homing orbs chase nearby enemies. Each upgrade adds another orb per cast. |

Weapon upgrades improve one property each: Cannon adds a ball, Harpoon adds pull strength, Mines add blast radius, Lightning adds a target, Whirlpool adds radius, and Arcane Orbs adds one orb per cast. Damage and firing cadence stay fixed across weapon ranks. Upgrade cards show the next level’s benefit.

Four boat upgrades keep choices simple: **Hull** (+25 max health), **Speed** (+10% sailing speed), **Reload** (+12% fire rate), and **Reach** (+15% attack area). Hull upgrades leave current health unchanged; repairs are a separate harbor action. Choose your boat before setting sail; it stays fixed for the whole voyage.

## Structure

- `source/core/StartingArea.cs`: shared starting positions, fixed home scenery/styles and dockside spawn.
- `source/core/OceanWorld.cs`: seed-and-coordinate geography, collision, bounded 5×5 chunk streaming, sparse discovery/depletion history.
- `source/core/SpawnDirector.cs`: original distance-based credit and population tuning, encounter lulls, boss escort ceiling.
- `source/core/Voyage.cs`: engine-independent movement, combat, fishing, economy, progression and endings.
- `source/presentation/Game.cs`: input, menus, HUD, saved progression and manual review captures.
- `source/presentation/OceanView3D.cs`: read-only native presentation, bounded streaming and actor synchronization.
- `NativeStage3D.cs`: shared orthographic camera, lighting, water, screen projection and click unprojection.
- `EnvironmentArt3D.cs`, `ActorArt3D.cs`, `ActorEquipment3D.cs`, `ActorGeometry.cs`: reproducible scenery, hulls, fittings and creatures.
- `Effects3D.cs`, `EffectsGeometry.cs`, and the Godot shaders: submerged schools, curved wakes, weapon effects and matte surface animation.

World generation has independent coordinate-local randomness; combat, upgrade offers, and fishing use separate streams. Each school is consumed when casting starts, so cancelling cannot retry or reroll it. Fishing holds the boat still while voyage time, monsters, attacks, automatic weapons and effects keep advancing. Reel or cancel to sail away. Defeat or victory ends an active cast; earned upgrades wait until the cast finishes. Distant chunks unload; school depletion survives their return. Sparse exploration history grows with visited places, while active chunks and visual caches are bounded.

See `docs/OBJECTIVE.md` for scope, `docs/QUALITY.md` for current validation and remaining gaps, and `docs/RESEARCH.md` for research provenance. No simulation harness or automated test results stand in for actual play.

LVL is aligned to the far top-right edge, separate from the north-up nautical chart below. Islands use shoreline outlines, harbors use anchors, fish use wave marks, and the center arrow follows your heading. A rim anchor points home when distant. Voyage objectives remain in pause.

Boat selection contains only the boat choice, Set Sail and Back. Every new run, including retry, uses the fixed starting area and a fresh offshore seed; seeds are internal diagnostics only.

The title is the actual fixed starting area: cottage upper-left, island lower-right and chosen boat alongside the wooden dock, with open water behind the centered logo and buttons. Set sail fades the menu while the boat remains stationary beside the dock. Movement starts only with player input; the camera keeps the title framing until the boat moves, then eases into normal tracking. Home geography and styles are identical on every new voyage; the offshore ocean remains seeded and randomized. Title and pause actions share inset navy/turquoise buttons, a gold keyboard-focus outline, and original code-drawn sail, key, chart, chest, book and home icons. Menus use compact navy panels, cream text, turquoise selection and gold purchase controls. Harbor and level-up offers share three equal cards with original code-drawn symbols and concise benefits. Hover motion and purchase pulses provide brief feedback.

The world follows the flat-shaded nautical diorama reference: broad matte color faces, quiet petrol-teal water, simple polygon shallows, warm sandy islands, angular rocks and palms, and compact cream cottages with solid pitched roofs. Small surface grain, deck seams, dense foliage and detailed water normals are removed. Wakes use two restrained curved ribbons sampled from actual movement. Mage carries an upright violet crystal; Gunboat cannon/harpoon fittings aim at their targets. Fish are subdued submerged forms, with no overhead markers. The reference image is never shipped as gameplay art.

The orthographic camera retains 0.74× scale and 0.84 ground-plane foreshortening. Simulation positions map to `(x/100, 0, y/100)`. HUD anchors and sailing clicks use that same camera. The simulation is engine-independent C#; all native integration is C#/.NET, Godot resources or shaders. No GDScript, imported models, external art packs or image-generated gameplay assets are used.

`art-sample.tscn` is a separate native art proof containing a boat, crab, cottage, island and water. Run it with `./run.command art-sample.tscn`. Tab switches inspection scale; F12 saves the rendered frame under `evidence/`. It contains no gameplay voyage or injected state.

## Sailing encounters

The bow turns responsively while the hull keeps a short drift. Boost gives an immediate kick and reaches 2.05× normal speed, with a brighter, wider wake; each new burst costs 8 boost plus the usual drain. Releasing steering slows the boat quickly. Turquoise current arrows show the direction of flow, adding up to 125 world units/second per lane (150 total cap). Steering against a current remains possible.

Sail over floating treasure for 12–20 run gold, or salvage wrecks between rocks for 35–55 gold. Both are collected automatically once per location per run, disappear from the chart after collection, and remain depleted when chunks reload. The home waters include one of each encounter; farther discoveries vary by seed. Encounters do not award silver.

Mines last up to 10 seconds and are limited to eight active mines. Harpoons pull surviving targets over 0.4 seconds, a thicker rope snap shows stronger pulls. Cannonballs have one bounce at every rank. Harpoon upgrades add 160 pull speed; mine and whirlpool upgrades add 30 radius. Arcane Orbs steer toward nearby enemies; no weapon requires lining up a side of the boat.

## Readability and sailing flow

Treasure has a rounded metal-banded lid, fishing schools use five subdued fish, and salvage wrecks have a tall broken mast. Offshore islands are larger and less frequent, with clustered shore rocks and palm, rock-spire or stranded-mast landmarks. Harbors occur on a two-chunk lattice to support regular refits; ordinary islands leave broad open lanes.

Friendly shot trails and hit particles are subdued and brief; coral enemy shots draw above friendly effects. Weapon fittings reflect equipped weapons and ranks; whirlpool art uses the exact attack radius, and harpoon ropes strengthen with pull upgrades. Soaked status, its slowing effect and its damage bonuses have been removed entirely.

The selected visual target and native acceptance criteria are documented in `docs/ART_DIRECTION.md`; current verification and its limits are in `docs/QUALITY.md`.
