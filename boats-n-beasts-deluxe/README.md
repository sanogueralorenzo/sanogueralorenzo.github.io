# Boats ’n’ Beasts Deluxe

Pilot a pirate ship through a procedural archipelago. Defend Breakwater, patrol Gull Shoal, and defeat the keeper at Smuggler’s Light. Cross the keeper’s marked lunge and close in when it is exposed. Signal Crownclaw from a lit beacon after two, or light all three to draw it out with weakened armor. It rises at 8:00 if you wait. Bait Crownclaw’s charge into rock to keep its shell open longer.

## Play

| Input | Action |
| --- | --- |
| WASD, arrows, or left stick | Steer |
| Left-click | Plot a course. Gull Shoal plots a patrol loop, and Smuggler’s Light plots an approach to the edge of the duel. |
| Right-click | Cancel the course |
| Space, Shift, or RB | Boost |
| E or controller X | Use Broadside, Breakwater, or Slipstream |
| F or controller A | Signal at a lit beacon or tie up at the repair berth |
| Tab or controller Y | Pause at the voyage chart to review discoveries and plot a course |
| Esc or Start | Pause |

Click a current’s arrow on the chart to plot a downstream passage. Sailing with the flow recharges boost faster and makes it last longer.

Level-ups fit up to three weapons and improve the hull, engine, reload, and reach. Choose a specialty at level 5. Every third level can offer a weapon swap when the deck is full. Swaps keep the slot’s rank and the boat’s starting weapon. Pair Cannon with Lightning for Stormshot, Harpoon with Mines for Tripwire, or Whirlpool with Arcane Orbs for Riptide.

Tow wreck cargo to a beacon for a refit and repairs. Choose a beacon to reserve that buyer, or right-click to clear the choice. Salvagers can tow farther for 4 extra silver at the marked beacon. Intercept the drifting cache before it sinks for XP, silver, and boost. Beach chests grant XP, barrels repair hull, and every four consecutive kills earn chain rewards. A last-second blast escape recovers boost and extends an active chain. Tie up at the harbor berth once for up to 50 hull. Moving or taking a hit interrupts repairs.

Use silver to unlock Salvager and Stormchaser when charting a voyage. In Stormchaser, dodge marked lightning or lure beasts into it. Win with three kills inside lightning marks to earn Thunderhead. Select a replayable time in the Captain’s Log to sail the same record chart. Daily charts rotate at midnight UTC and award 5 silver for a first daily clear. The previous six charts are available for timed practice.

## Run and preview

Requires .NET 10 SDK and Godot 4.7.2 .NET. The live preview watcher also requires Python 3.

```sh
./run.command
./run.command --preview
./run.command --preview --once
dotnet run --project tests/WorldChecks.csproj
```

Set `GODOT_BIN` to the Godot .NET executable if it is outside the standard location, and `DOTNET_ROOT` if needed. Add `--import` to refresh resources. The preview lists its shortcuts in the window. Art and audio are generated in code. The score adds layers as beasts close in and Crownclaw rises. The Deluxe project stores its progress and art-preview preferences in its own Godot user directory.
