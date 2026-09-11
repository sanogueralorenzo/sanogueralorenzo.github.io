# Boats ’n’ Beasts

A procedural sailing prototype with automatic combat, island obstacles and boat upgrades. The game loop is still being explored.

## Run and preview

Requires .NET 10 SDK and Godot **4.7.2 .NET** with Forward+. The preview watcher also requires Python 3.

```sh
./run.command                 # Play
./run.command --preview       # Live art preview
./run.command --preview --once # Single preview launch
```

Set `GODOT_BIN` and `DOTNET_ROOT` if the launcher cannot find them. Add `--import` when resource imports need refreshing.

Saving C# rebuilds and restarts the preview; shader edits refresh without a build. Failed builds keep the last preview open. Island selection and viewing scale survive restarts. Close the window or press Ctrl+C to stop.

Preview controls: **Space** shape, **R** size, **V** seed, **B** reference crescent, **P** prison, **T** watchtower, **Tab** scale, **F5** refresh, **F12** capture.

Select **2** tavern, **7** shipwreck, **8** sea cave or **9** ancient arch; **+ / −** adjusts that model's size independently and remembers it across preview restarts. Sizes fit the available land. Production defaults and per-build overrides live in `LandmarkSizes` in `source/presentation/EnvironmentLandmarks3D.cs` (`EnvironmentArt3D.Build(place, new LandmarkSizes(Tavern: 1.6f))`).

## Current gameplay

- Steer with WASD/arrows or click a destination; Space/Shift boosts and Escape pauses.
- Choose Gunboat, Aura or Mage. Weapons fire automatically; two weapon slots are available.
- Level-ups offer weapon or boat upgrades. Beach chests grant XP; floating barrels restore health.
- Survive to defeat Crownclaw. The harbor is currently scenery.
- The speed button cycles ×1 / ×2 / ×3 / ×10 / ×20.

## Visual style

Use broad matte shapes, warm light, quiet teal water, irregular sandy islands and readable wooden pirate ships. Prisons occupy rare large island destinations; watchtowers, taverns, shipwrecks, sea caves and ancient arches join the existing ruins, groves and cliffs. Landmarks are decorative. Follow the [reef reference](docs/island-reference.png) and [diorama reference](docs/visual-restart/flat-diorama-reference.png); generate all gameplay art in code.

## Install on macOS

Use matching .NET export templates and set `GODOT_BIN` to the engine executable. Export only for a requested installation or packaging change:

```sh
mkdir -p build
"$GODOT_BIN" --headless --path . --export-release macOS "build/Boats n Beasts.app"
ditto "build/Boats n Beasts.app" "$HOME/Applications/Boats n Beasts.app"
codesign --force --deep --sign - --preserve-metadata=entitlements,identifier,runtime "$HOME/Applications/Boats n Beasts.app"
codesign --verify --deep --strict "$HOME/Applications/Boats n Beasts.app"
```

This creates a local app and preserves existing saves. Public distribution requires signing and notarization.

See [agent workflow](AGENTS.md).
