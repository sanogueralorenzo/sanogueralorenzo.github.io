# Boats ’n’ Beasts Deluxe

Pilot a pirate ship through a procedural archipelago. Defend Breakwater, patrol Gull Shoal, and defeat the keeper at Smuggler’s Light to draw out Crownclaw, or face it at 8:00. Your crew fires when it has a clear shot. Steer across Crownclaw’s marked charge lane or bait it into rock to keep its shell open longer.

## Play

| Input | Action |
| --- | --- |
| WASD, arrows, or left stick | Steer |
| Left-click | Plot a course to a point or chart marker. Click Gull Shoal to sail a patrol loop. |
| Right-click | Cancel the course |
| Space, Shift, or RB | Boost |
| E or controller X | Use Broadside, Breakwater, or Slipstream |
| Tab or controller Y | Pause at the voyage chart to review discoveries and plot a course |
| Esc or Start | Pause |

Level-ups fit up to three weapons and improve the hull, engine, reload, and reach. Choose a specialty at level 5. Pair Cannon with Lightning for Stormshot, Harpoon with Mines for Tripwire, or Whirlpool with Arcane Orbs for Riptide. Tow cargo from the wreck marked on the compass to any beacon for a refit and repairs. Beach chests grant XP, barrels repair hull, and every four consecutive kills earn chain rewards.

The Captain’s Log tracks your fastest win for each boat and charter. Spend silver from beacons, chains, and victories on the Salvager and Stormchaser charters. The Sail Locker lets you preview and equip sails earned through salvage, a three-beacon victory, and a daily clear. The daily challenge rotates the boat, chart, and objective at midnight UTC and pays a first-clear silver bonus.

## Run and preview

Requires .NET 10 SDK and Godot 4.7.2 .NET. The live preview watcher also requires Python 3.

```sh
./run.command
./run.command --preview
./run.command --preview --once
dotnet run --project tests/WorldChecks.csproj
```

Set `GODOT_BIN` to the Godot .NET executable if it is outside the standard location, and `DOTNET_ROOT` if needed. Add `--import` to refresh resources. The preview lists its shortcuts in the window. Art and audio are generated in code. The Deluxe project stores its progress and art-preview preferences in its own Godot user directory.
