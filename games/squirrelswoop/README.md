# Squirrel Swoop

An endless downhill glide through a living mountainside. Bank into a sunlit meadow, follow winding water, or thread the deep woods. All three landscapes share one continuous mountain: fly across them whenever you like.

## Play

Install **Godot 4.7.2** and use a GPU supporting **Forward+** (Metal on Apple Silicon; Vulkan or Direct3D 12 on supported desktops). Forward+ is mandatory in the editor, development runs, and exports. Game launches with unsupported renderer overrides exit with an error; automatic OpenGL fallback is disabled. From the repository root:

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

Settings offer sound volume, gentle ground assistance, reduced camera motion, and inverted pitch. Ground assistance trades some momentum for lift near rising terrain after dive is released. An early manual recovery preserves more speed. Turning assistance off removes the automatic ground rescue; steering and obstacles always remain yours to manage. Close passes reward risk, but distance and uninterrupted flight also earn points. No unlocks or grinding.

## The mountain

- Terrain uses a continuous world-coordinate height field; flight collision samples the exact triangles rendered on screen. The variable-width stream, stones, and fitted roots share that ground surface.
- A seeded section generator mixes groves, rocky shelves, boulder gardens, fern clearings, and recovery stretches. Unequal, seed-derived formation spans combine anticipation, challenge, and recovery. Difficulty builds gradually outside preserved passages; meadow density stays low.
- Each landscape has multiple passages, and a long diagonal clearing connects them. Placement reserves clearance across bends and neighboring landscapes. The low woodland openings protect ordinary gliding height; higher lines can meet solid overhead limbs. There are no route selectors, gates, or side walls.
- A moving 7 × 9 section window generates ahead and unloads behind. Live generation is divided into short work intervals; retries cancel unfinished sections. Mesh resources are shared, vegetation is instanced, and distant pine crowns use simpler geometry. Per-section collision cells avoid scanning entire groves every frame.
- Collision sweeps the squirrel's forgiving body volume through terrain, curved tapered trunks, projecting branches, roots, fallen timber, and rock volumes each physics frame. Foliage, fur, and wing tips are soft.

Records and settings are saved in Godot's `user://swoop.cfg` (on macOS, `~/Library/Application Support/Godot/app_userdata/Squirrel Swoop/`). Records are preserved when returning to the summit or quitting as well as after a collision. Screenshots use that same directory.

## Desktop exports and rendering

The default window and captured gameplay resolution is **1280 × 800**, with a 1440 × 900 logical interface layout. Native 3D MSAA keeps geometry and needle edges crisp; the interface is drawn separately. Startup prints the actual renderer, driver, and GPU, for example `forward_plus / metal / Apple M3 Max (Apple9)`.

Install the matching 4.7.2 export templates, then run from the repository root:

```sh
mkdir -p games/squirrelswoop/build
godot --headless --path games/squirrelswoop --export-release "macOS"
# Other included presets: "Windows Desktop", "Linux Desktop"
```

Open `games/squirrelswoop/build/Squirrel Swoop.app` on macOS. The app contains the complete procedural game and requires neither this repository nor Godot to be installed. macOS exports use local ad-hoc signing; public distribution would require your own signing/notarization. Windows and Linux builds are exportable presets; native execution on those operating systems has not been verified.

[Forward+ verification and comparisons](development/forward-plus/VERIFICATION.md) records the selected effects, rejected alternatives, renderer confirmation, manual play, desktop exports, and measured performance.

## Development and evidence

[Refinement evidence](development/refinement/REFINEMENT.md) records the improvement cycles, comparable captures, final runtime findings, frame times, and remaining limits. The [original verification notes](development/VERIFICATION.md) separate observed runtime behavior, code review, and subjective visual/feel judgments. No automated tests were created. The optional loopback review console in `game.gd` exists for discrete manual flight controls, scene inspection, screenshots, and live telemetry; it is disabled in normal play. See [manual review controls](development/REVIEWING.md).

Everything rendered and heard in the game is generated locally: terrain, tree and rock meshes, pine textures, fur, gliding membranes, animation, shaders, motes, wind, birds, and feedback tones. The supplied image lives under `development/visual-target.png` as a reference and is excluded from Godot's asset scan. It is never displayed as gameplay. The locally adapted sky derives from this repository's **Cozy Sora** project; its restrained ambient-contact and filtered-shadow techniques also informed the lighting. Squirrel Swoop has no runtime dependency on it.
