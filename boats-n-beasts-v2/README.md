# Boats ’n’ Beasts V2

An original Godot pirate roguelike. Last Light Quay loses its bell in **The Silent Watch**. Join Lio and Vara to recover it, dock at Bellwether and bring its keeper home. **The Far Ledger** follows the crew across eight regions, from Cinder Narrows to the Unnumbered Sea. The crew’s hearings decide which orders and witnesses appear. Cleared orders can be replayed from the ship’s log.

## Play

Requires .NET 10 and Godot **4.7.2 .NET** with Forward+. Set `GODOT_BIN` to the engine executable and `DOTNET_ROOT` to the SDK directory if needed.

```sh
./run.command
./run.command --preview --once
```

In the harbor, click a station or walk with WASD and press E. Use the crew table for conversations, the galley for permanent provisions and the berth for departures. The chart shows available island stories. The outfitter opens after the first bell ringing. Escape pauses a run. Defeat and retreat bank the silver collected that run. Victory can open a landing, bring someone home or change the quay. Progress saves locally.

| At sea | Ashore |
| --- | --- |
| WASD or arrows to steer | WASD or arrows to walk |
| Hold Space to fire, turn side-on for a broadside. Click to aim on charted voyages | Hold J or left click to slash |
| Q to grapple, Shift to surge | K to call Lio’s hook, Space to dodge |
| E to use a repair kit, number keys to choose routes and refits | E to work, open gates or board. Use 1–4 to trade at camp |

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
