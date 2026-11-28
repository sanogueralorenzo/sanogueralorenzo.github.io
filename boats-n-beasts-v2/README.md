# Boats ’n’ Beasts V2

An original Godot pirate roguelike. Last Light Quay loses its bell in **The Silent Watch**. Join Lio and Vara to recover it, dock at Bellwether and bring its keeper home. **The Far Ledger** follows the crew across eight regions, from Cinder Narrows to the Unnumbered Sea. **The Walking Tide** takes the signed chart into eight outer regions where islands migrate and a nursery fleet needs shelter. The crew’s hearings decide which orders and witnesses appear. Cleared orders can be replayed from the ship’s log.

## Play

Requires .NET 10 and Godot **4.7.2 .NET** with Forward+. Set `GODOT_BIN` to the engine executable and `DOTNET_ROOT` to the SDK directory if needed.

```sh
./run.command
./run.command --preview --once
```

In the harbor, click a station or walk with WASD and press E. Use the crew table for conversations, the galley for provisions and the berth for departures. The chart shows four island stories per region. Plot an approach in the pilot book, then take local orders in any available island chain. Nell keeps the gifts from completed islands in the visitors’ book. After the first bell ringing, visit the outfitter and dry dock for ship classes, equipment and regional figureheads. Sit with Lio, Vara or Nell between watches to earn a keepsake. Press F to call on the equipped shipmate once per charted run.

Escape pauses a run. Defeat, retreat and an interrupted watch bank the silver collected on that attempt. Completing an order can open a landing, bring someone home or change the quay. Progress saves locally. The galley log records active hours ashore and afloat, total attempts and time to the first main-story clear.

| At sea | Ashore |
| --- | --- |
| WASD or arrows to steer | WASD or arrows to walk |
| Hold Space to fire, turn side-on for a broadside. Click to aim on charted voyages | Hold J or left click to slash |
| Q to grapple, Shift to surge | K to call Lio’s hook, Space to dodge |
| E to use a repair kit, number keys to choose routes and refits | E to work, open gates or board. Use 1–4 to trade at camp |

On a pilot survey, open the chart with M, sail to the second light and hail it with Q. Pin the crossing of the two bearings, sail there and cast the lead with E. Use R for a hull patch and hail the tender to file the survey. Press M for a district map on charted landings and Tab to cycle its targets.

On the Night Post, choose a lane on the packet chart, carry the letter through sea crossings and on-foot towpaths, and keep the cutter and crew fit for the final assignment. On a nursery watch, answer a calf’s song with 1–3 and guide it to the mother. Use Q to soothe, E to gather kelp or feed, and M to consult the chart.

Prize Watch uses sail markings, close inspection and on-deck crew work to identify and extract a prize. The Underways lead through connected rooms, evidence chambers and surface sorties to an island guardian. Escape opens the controls for the current watch.

## Art preview

All art is generated in code. Use `./run.command --preview` for the Python 3 live watcher. The preview opens on the lighthouse at gameplay scale and displays the keys for island selection, scale, crew and camera. Pass `--import` to the launcher to refresh the resource cache.

## Install on macOS

Use matching .NET export templates and set `GODOT_BIN` to the engine executable. Export only for a requested installation or packaging change:

```sh
mkdir -p build
"$GODOT_BIN" --headless --path . --export-release macOS "build/Boats n Beasts V2.app"
ditto "build/Boats n Beasts V2.app" "$HOME/Applications/Boats n Beasts V2.app"
codesign --force --deep --sign - --preserve-metadata=entitlements,identifier,runtime "$HOME/Applications/Boats n Beasts V2.app"
codesign --verify --deep --strict "$HOME/Applications/Boats n Beasts V2.app"
```

This creates a local app and preserves existing saves. Public distribution requires signing and notarization.

See [agent workflow](AGENTS.md).
