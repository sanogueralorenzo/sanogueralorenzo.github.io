# Squirrel Swoop

An endless downhill glide through a living mountainside. Bank into a sunlit meadow, follow winding water, or thread the deep woods. All three landscapes share one continuous mountain: fly across them whenever you like.

## Play

Install Godot 4 (developed and played with **Godot 4.7.2**, Compatibility renderer). From the repository root:

```sh
godot --path games/squirrelswoop
```

Or open `project.godot` in Godot and press **F6** on `main.tscn`, or **F5** to run the project. There are no downloads, packages, external assets, or build steps. A fresh checkout runs directly; the scripts preload their dependencies explicitly.

| Control | Action |
| --- | --- |
| Enter | Leave the summit |
| A / D or Left / Right | Bank across the mountainside |
| W / S or Up / Down | Lower the nose / pull up |
| Hold Shift or Space | Tuck into a faster dive |
| Release dive | Spread the membrane and recover lift |
| Escape | Pause / resume |
| R after a crash | Retry the same mountain |
| N after a crash | Start a new random mountain |
| F3 | Show performance and flight diagnostics |
| F12 | Save a gameplay screenshot in Godot's user-data folder |

Gamepad: left stick banks and pitches, right trigger dives, A launches/retries, Y starts a new mountain after a crash, and Start pauses. Gamepad mappings are implemented; physical-controller play has not been verified.

For a reproducible mountain:

```sh
godot --path games/squirrelswoop -- --seed=482193
```

To get comfortable, bank left into the meadow and release the controls. Neutral trim settles into a descent. Short dives trade clearance for speed. Pulling up spends that speed; low momentum limits lift, so holding up cannot climb above the mountain indefinitely. You always descend; the squirrel does not flap or hover. Look several trees ahead and release dive early.

Settings offer sound volume, gentle ground assistance, reduced camera motion, and inverted pitch. Ground assistance adds lift near rising terrain after dive is released; it does not steer or avoid trees. Close passes reward risk, but distance and uninterrupted flight also earn points. No unlocks or grinding.

## The mountain

- Terrain uses a continuous world-coordinate height field. The stream and its banks use the same centerline.
- A seeded section generator mixes groves, rocky shelves, boulder gardens, fern clearings, and recovery stretches. Each 320 m section changes the local formations. Difficulty builds gradually outside preserved passages; meadow density stays low.
- Each landscape has multiple broad passages, and a long diagonal clearing connects them. Corridors reserve obstacle clearance across bends, rather than clearing only the exact center of a tree. There are no lanes, route selectors, gates, or side walls.
- A moving 7 × 9 section window generates ahead and unloads behind. Mesh resources are shared, vegetation is instanced, and distant pine crowns use simpler geometry.
- Collision sweeps the squirrel's forgiving body volume through terrain, tapered trunks, solid branches, and rock volumes each physics frame. Foliage, fur, and wing tips are soft.

Records and settings are saved in Godot's `user://swoop.cfg` (on macOS, `~/Library/Application Support/Godot/app_userdata/Squirrel Swoop/`). Records are preserved when returning to the summit or quitting as well as after a collision. Screenshots use that same directory.

## Development and evidence

[Verification notes](development/VERIFICATION.md) separate observed runtime behavior, code review, and subjective visual/feel judgments. No automated tests were created. The optional loopback review console in `game.gd` exists for discrete manual flight controls, scene inspection, screenshots, and live telemetry; it is disabled in normal play. See [manual review controls](development/REVIEWING.md).

Everything rendered and heard in the game is generated locally: terrain, tree and rock meshes, pine textures, fur, gliding membranes, animation, shaders, motes, wind, birds, and feedback tones. The supplied image lives under `development/visual-target.png` as a reference and is excluded from Godot's asset scan. It is never displayed as gameplay. The locally copied sky and brush-filter shaders derive from this repository's **Cozy Sora** project; Squirrel Swoop has no runtime dependency on it.
