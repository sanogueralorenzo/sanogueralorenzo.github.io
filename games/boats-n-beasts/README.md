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

Preview shortcuts follow keyboard order: **Q–P** islands and landmarks, **A–L** scenery and size/crew controls, **Z/X** turn the boat, **C** view, **V** refresh, **B** capture. The preview shows every binding; **Q** cycles island samples.

Select **1** lighthouse, **2** tavern, **3** market stall, **6** windmill, **7** shipwreck, **8** sea cave or **9** ancient arch; **+ / −** adjusts that model's size independently and remembers it across preview restarts. **O** toggles the selected wreck between land and water. Sizes fit the available land; sea wreck size follows its place radius. Production defaults and per-build overrides live in `LandmarkSizes` in `source/presentation/EnvironmentLandmarks3D.cs` (`EnvironmentArt3D.Build(place, new LandmarkSizes(Tavern: 1.6f))`).

Run the focused sea-wreck collision and generation checks with `dotnet run --project tests/WorldChecks.csproj`.

## Current gameplay

- Steer with WASD/arrows or click a destination; Space/Shift boosts and Escape pauses.
- Choose Gunboat, Aura or Mage. Weapons fire automatically; two weapon slots are available.
- Level-ups offer weapon or boat upgrades. Beach chests grant XP; floating barrels restore health.
- Survive to defeat Crownclaw. The harbor is currently scenery.
- The speed button cycles ×1 / ×2 / ×3 / ×10 / ×20.

## Visual style

Use broad matte shapes, warm light, quiet teal water, irregular sandy islands and readable wooden pirate ships. Prisons occupy rare large island destinations; watchtowers, taverns, lighthouses, market stalls, windmills, shipwrecks, sea caves and ancient arches join the existing ruins, groves and cliffs. Island landmarks are decorative; sea wrecks are solid obstacles with hull-shaped collision. Follow the [reef reference](docs/island-reference.png) and [diorama reference](docs/visual-restart/flat-diorama-reference.png); generate all gameplay art in code.

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
