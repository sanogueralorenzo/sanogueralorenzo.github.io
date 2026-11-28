# Boats ’n’ Beasts V2

A procedural sailing prototype with automatic combat, island obstacles and boat upgrades. V2 has its own save and preview settings.

## Run and preview

Requires .NET 10 SDK and Godot **4.7.2 .NET** with Forward+. The preview watcher also requires Python 3.

```sh
./run.command                 # Play
./run.command --preview       # Live art preview
./run.command --preview --once # Single preview launch
```

Set `GODOT_BIN` and `DOTNET_ROOT` if the launcher cannot find them. Add `--import` when resource imports need refreshing.

On first launch, the preview opens on the lighthouse island at gameplay scale. Saving C# rebuilds the preview, while shader edits refresh without a build. Island selection and viewing scale survive restarts. Close the window or press Ctrl+C to stop.

Preview shortcuts follow keyboard order: **Q–P** islands and landmarks, **A–L** scenery and size/crew controls, **Z/X** turn the boat, **C** view, **V** refresh. The preview shows every binding; **Q** cycles island samples.

Select **R** lighthouse, **T** tavern, **Y** market stall, **U** windmill, **O** sea cave or **P** ancient arch. **H/J** adjusts the selected model’s size and remembers it across preview restarts. Production defaults and per-build overrides live in `LandmarkSizes` in `source/presentation/EnvironmentLandmarks3D.cs` (`EnvironmentArt3D.Build(place, new LandmarkSizes(Tavern: 1.6f))`).

Run the focused world-generation checks with `dotnet run --project tests/WorldChecks.csproj`.

## Current gameplay

- Steer with WASD/arrows or click a destination; Space/Shift boosts and Escape pauses.
- Choose Gunboat, Aura or Mage. Weapons fire automatically; two weapon slots are available.
- Level-ups offer weapon or boat upgrades. Beach chests grant XP; floating barrels restore health.
- Survive to defeat Crownclaw. The harbor is currently scenery.
- The speed button cycles ×1 / ×2 / ×3 / ×10 / ×20.

## Visual style

Warm sandstone, crisp violet shadows and bands of turquoise shallows frame the open teal sea. Coral accents distinguish danger and landmarks, while cream sails and wakes trace the player’s course. All gameplay art is generated in code.

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
