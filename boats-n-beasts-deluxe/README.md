# Boats ’n’ Beasts Deluxe

Pilot a pirate ship through a procedural archipelago. Defend Breakwater, patrol Gull Shoal, and defeat the keeper at Smuggler’s Light to draw out Crownclaw, or face it when the voyage reaches 8:00. The crew fires automatically while you navigate, dodge, and time your boat’s maneuver.

## Play

| Input | Action |
| --- | --- |
| WASD, arrows, or left stick | Steer |
| Left-click | Set a sailing destination |
| Space, Shift, or RB | Boost |
| E or controller X | Use Broadside, Breakwater, or Slipstream |
| Esc or Start | Pause |

Level-ups fit up to three weapons and improve the hull, engine, reload, and reach. Choose a specialty at level 5. Tow cargo from the wreck marked on the compass to any beacon for a refit and repairs. Beach chests grant XP, barrels repair hull, and every four consecutive kills earn chain rewards. Claim silver from beacons, chains, and victories. Spend it in the Captain’s Log to unlock the Salvager and Stormchaser charters. The log tracks your fastest win for each boat and charter.

## Run and preview

Requires .NET 10 SDK and Godot 4.7.2 .NET. The live preview watcher also requires Python 3.

```sh
./run.command
./run.command --preview
./run.command --preview --once
dotnet run --project tests/WorldChecks.csproj
```

Set `GODOT_BIN` to the Godot .NET executable if it is outside the standard location, and `DOTNET_ROOT` if needed. Add `--import` to refresh resources. The preview lists its shortcuts in the window. Art and audio are generated in code. The Deluxe project stores its progress and art-preview preferences in its own Godot user directory.
