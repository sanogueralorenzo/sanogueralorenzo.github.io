# Cozysora — 夏の道

A standalone Godot 4 recreation of [Natsu no Michi](https://cosy-japan.vercel.app/): explore a summer coastal village as a tabby cat or a seagull. The world, characters, textures, animation, and sound are generated at runtime. There are no downloaded models, images, fonts, recordings, animation files, or JavaScript dependencies in the project.

Open `project.godot` in Godot 4.7 or run:

```sh
godot --path games/cozysora
```

Forward+ is the intended renderer. The first launch grows the terrain and foliage; later launches reuse generated resources in Godot's application user-data directory. Removing those caches is safe: they are regenerated from the source. The project does not need a network connection.

## Controls

Click the title card to start. Choose a character there, or press **Tab** while playing.

| Control | Cat | Seagull |
| --- | --- | --- |
| Mouse | Look around | Aim flight |
| W / A / S / D | Move relative to camera | Fly / bank left / brake / bank right |
| Shift | Sprint | Boost |
| Space | Jump and meow | Climb / take off |
| C | — | Descend |
| Left click | — | Cry |
| Escape | Release mouse / show menu | Release mouse / show menu |

The seagull glides without input and can settle on the ground. Switching back to the cat returns to traversable ground; unsafe coastal positions fall back to the cat's last location.

## Construction

- `scripts/world.gd` owns the deterministic height field, Catmull–Rom road network and spatial queries, generated road/zone map, terrain collision, coastal furniture, sky, ocean, light, fog, and scene assembly.
- `scripts/vegetation.gd` generates leaf silhouettes and bark textures, branching trees, card canopies, hedges, broad leaves, rice-adjacent flora, grass, flowers, and location-specific planting. Instancing and spatial batches retain the dense world without creating a node per blade.
- `scripts/settlements.gd` owns the farm, paddies, village houses and utility yard, shrine, vending areas, elevated railway and moving train. Timber, metal, roof tile, concrete, stone, chain-link, and vending surfaces are generated from code. Static details are combined by material and spatial cell.
- `scripts/player.gd` generates and animates the characters, handles locomotion and collision, follows the player with the camera, and synthesizes the soundscape and vocalizations.
- `scripts/interface.gd` builds the title card and controls with engine UI and installed system-font fallbacks. No font is bundled.
- `scripts/summer_life.gd` animates butterflies and drifting particles.
- `shaders/` contains original Godot implementations of wind, foliage lighting, ground materials, cloud and sea fields, and a painterly screen treatment.

## Reference and verification views

The technical specification was the deployed site's client bundles, inspected on 4 September 2026. Their source-specific formulas, dimensions, palette, area coordinates, camera presets, and control constants informed the implementation; the original JavaScript is not included or executed. See [REFERENCE.md](REFERENCE.md) for the system mapping.

For repeatable runtime visual inspection, the project exposes the same named viewpoints as the reference:

```sh
godot --path games/cozysora -- --shot --view=coast --capture=/tmp/coast.png --quit-after-capture
godot --path games/cozysora -- --shot --capture-dir=/tmp/cozysora-views --quit-after-capture
```

Available views: `coast`, `paddy`, `farm`, `rail`, `village`, `alley`, `vending`, `viaduct`, `shrine`, `top`. Omitting `--view` uses the normal cat camera. `--gull` starts as the seagull. Capture mode hides the menu; the named views preserve the reference's camera position, eye-height offset, pitch, yaw, and vertical field of view. Captures are written only to the explicitly supplied path.

Verification uses rendered runtime inspection and manual play, not a test suite. See [VERIFICATION.md](VERIFICATION.md) for the reviewed behavior, performance observations, and remaining manual verification gap.
