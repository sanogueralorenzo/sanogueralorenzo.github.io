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

Level-ups fit up to three weapons and improve the hull, engine, reload, and reach. Choose a specialty at level 5. Every third level can offer a weapon swap when the deck is full. Swaps keep the slot’s rank and the boat’s starting weapon. Pair Cannon with Lightning for Stormshot, Harpoon with Mines for Tripwire, or Whirlpool with Arcane Orbs for Riptide.

Tow wreck cargo to a beacon for a refit and repairs. Choose a beacon to reserve that buyer, or right-click to clear the choice. Salvagers can tow farther for 4 extra silver at the marked beacon. Intercept the drifting cache before it sinks for XP, silver, and boost. Beach chests grant XP, barrels repair hull, and every four consecutive kills earn chain rewards. A last-second blast escape recovers boost and extends an active chain. Tie up at the harbor berth once for up to 50 hull. Moving or taking a hit interrupts repairs.

Use silver to unlock Salvager and Stormchaser when charting a voyage. In Stormchaser, dodge marked lightning or lure beasts into it. Win with three kills inside lightning marks to earn the Thunderhead sail. The voyage report shows your final build, personal best, and progress toward the next charter. The Captain’s Log tracks your fastest hunts. Daily challenges rotate at midnight UTC and pay a first-clear silver bonus.

## Run and preview

Requires .NET 10 SDK and Godot 4.7.2 .NET. The live preview watcher also requires Python 3.

```sh
./run.command
./run.command --preview
./run.command --preview --once
dotnet run --project tests/WorldChecks.csproj
```

Set `GODOT_BIN` to the Godot .NET executable if it is outside the standard location, and `DOTNET_ROOT` if needed. Add `--import` to refresh resources. The preview lists its shortcuts in the window. Art and audio are generated in code. The score adds layers as beasts close in and Crownclaw rises. The Deluxe project stores its progress and art-preview preferences in its own Godot user directory.
