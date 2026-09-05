# Cozy Sora

Cozy Sora is an original procedural Godot game about quiet coastal exploration. Seabreeze Village evokes Japanese summers; Harbor Hills is a fictional district of steep streets, cypress gardens and bay views. Its code, shaders, meshes, textures, animation, and audio are authored or generated specifically for this project. No external game assets or source code are bundled.

Open `project.godot` in Godot 4.7 and run the main scene, or use:

```sh
godot --path games/cozysora
```

Choose **Seabreeze Village** or **Harbor Hills** on the destination screen and press **Play**. Wander Japanese coastal lanes and fields, or follow a cable car through a fictional hillside district above the bay. Explore as a cat or take flight as a seagull. Destination previews are in-game captures made by this project.

Forward+ is the intended gameplay renderer. First entry generates terrain and vegetation; subsequent visits reuse generated resources in Godot's application user-data directory. The loading screen reports the current stage. No network connection is needed. The selector itself builds immediately without generating the world.

## Controls

The selector and menus use standard Godot focus navigation: click or tap a button, use Tab / Shift+Tab or arrow keys and Enter / Space, or use a controller's D-pad and confirm button. Gold outlines identify focused controls. Scroll when a short viewport cannot show the whole panel.

| Action | Keyboard / mouse | Controller | Touch controls |
| --- | --- | --- | --- |
| Move / aim flight | WASD or arrow keys | Left stick | Left pad |
| Look | Mouse | Right stick | Drag on the right |
| Jump / climb | Space | A | Jump / Climb |
| Descend as seagull | C or Ctrl | B | Drop |
| Sprint / boost | Shift | LB | Hold Boost |
| Switch cat / seagull | Tab | Y | Switch |
| Seagull cry | Left click | X | Switching / takeoff also vocalizes |
| Pause / resume | Escape or Menu | Start | Menu |

The seagull glides without input and can settle on the ground. Harbor Hills also supports rooftop perching and switching on safe building surfaces; its low garden roofs have cat access ramps. Unsafe coastal positions fall back to the cat's last safe location or registered spawn.

**Menu → Back to destinations** unloads the map. Entering it again starts at its registered spawn. Menu pauses movement, map simulation, and audio; Settings changes sound volume, mute, and touch controls. Settings persist across maps and launches. Touch controls are enabled automatically on detected touch screens and can be enabled manually in Settings.

## Maps and ownership

- `scripts/application.gd` owns navigation, transitions, settings, loading, pause state, screenshot capture, and one disposable gameplay session.
- `maps/registry.tres` lists `CozyMapDefinition` resources. Each contains a stable ID, title, subtitle, description, scene path, project-owned preview, and spawn position / camera angles / character.
- `scripts/map.gd` is the small `CozyMap` scene contract. A map builds its own content, reports progress, and exposes ground height, walkable space, flight bounds, ambience parameters, and optional scenic viewpoints.
- `maps/seabreeze_village/map.tscn` owns the existing terrain, roads, coast, farm, paddies, village, shrine, vending areas, railway, train, vegetation, lighting, fog, particles, and world post-processing. Its construction lives in `world.gd`, `settlements.gd`, `vegetation.gd`, and `summer_life.gd`.
- `maps/harbor_hills/` owns the second district: sloping streets, row houses, shops, courtyards, cypress park, waterfront, moving cable car, local bell, vehicles, distant city, bridge and fog. See [its map notes](maps/harbor_hills/README.md).
- `scripts/player.gd` owns the common cat and seagull geometry, animation, locomotion, camera behavior, input, and audio synthesis. Ambient parameters belong to the map. Its camera and character nodes live inside the disposable session.
- `landing.gd`, `interface.gd`, `touch_controls.gd`, and `ui_theme.gd` are shared UI owned by the application. A map never creates a player, camera, menu, or settings panel.

See [MAPS.md](MAPS.md) for the scene lifecycle and exact registration steps. [DESIGN.md](DESIGN.md) describes Seabreeze Village's procedural systems; [VERIFICATION.md](VERIFICATION.md) records runtime inspection and platform limits.

## Scenic captures and diagnostics

The normal launch always opens destination selection. These explicit development options enter a map directly:

```sh
godot --path games/cozysora -- --map=seabreeze_village --profile
godot --path games/cozysora -- --map=harbor_hills --profile
godot --path games/cozysora -- --shot --view=coast --capture=/tmp/coast.png --quit-after-capture
godot --path games/cozysora -- --shot --capture-dir=/tmp/cozy-sora-views --quit-after-capture
```

`--shot` hides shared UI. Available Seabreeze Village views: `coast`, `paddy`, `farm`, `rail`, `village`, `alley`, `vending`, `viaduct`, `shrine`, `top`. Omitting `--view` uses the normal cat camera. `--gull` chooses the seagull for a direct map launch. `--capture=/tmp/landing.png` without a map or shot option captures the selector. `--touch` enables touch controls for a native pointer walkthrough. `--profile` reports frame rate, lifecycle state, and live player / camera / audio / orphan counts on transitions.

Verification uses runtime rendering, native interaction, and code review. No automated tests are included.

Harbor Hills capture views: `waterfront`, `commercial`, `residential`, `park`, `cable_car`, `stairs`, `garden`, `rooftops`, `flight`, `street_end`, and `top`. Pass `--map=harbor_hills` with the capture options to select that map.
