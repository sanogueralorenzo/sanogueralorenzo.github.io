# Last Cast

A small, independently runnable Godot 4 fishing roguelike. Walk a sunlit coastal harbor, read the water, earn a skiff, and decide when one more fish is worth the fading daylight.

## Launch

Developed and verified with **Godot 4.7.2** on macOS, using **Forward+**. Earlier Godot 4 releases have not been verified. A desktop GPU supporting Godot’s RenderingDevice backend is required; the verified Apple Silicon setup uses native Metal. OpenGL fallback is disabled, and the game refuses other rendering methods before loading a save.

From this repository:

```sh
godot --path games/lastcast
```

Or import `games/lastcast/project.godot` in Godot and press **F5** to run the main scene. There are no downloaded assets, packages, or services to install. Everything is generated locally by GDScript and Godot shaders. A keyboard and mouse are supported; controller bindings are not implemented.

To build the self-contained macOS app with matching Godot export templates installed:

```sh
mkdir -p games/lastcast/build
godot --headless --path games/lastcast --export-release macOS 'build/Last Cast.app'
open 'games/lastcast/build/Last Cast.app'
```

The export uses a dedicated application identifier so it can run alongside other Godot games. The local app is ad hoc signed; distribution signing and notarization are not configured. Generated builds are ignored by Git.

The default window and verified framebuffer are **1280×800** (1440×900 UI design coordinates). Startup prints `LAST_CAST_RENDERER method=forward_plus driver=metal device=…` on the verified Mac; Vulkan or Direct3D 12 may be used on other capable desktops. Do not supply `--rendering-method` overrides.

Normal launches pause when the window loses focus. For recording or deliberate background play, launch with `godot --path games/lastcast -- --keep-running-unfocused` (or append `--args -- --keep-running-unfocused` to the macOS `open` command). This only changes focus-loss pausing; it does not change fishing rules, game speed, rewards, or input. Use Esc to pause manually.

## Your first tide

1. Close the introduction and press **F** on the little shore pier. Pick a region/season and one expedition upgrade.
2. **T** cycles Float, Spinner, Jig. **G** cycles Drift, Twitch, Deep. The bottom cue names the current quarry. Changing setup shows its water hint; **J** lists signature recipes.
3. **F** starts a cast. Press **Space** when the placement meter reaches 55–80%. Every cast remains fishable; a precise cast brings the strike sooner.
4. Hold **Space** on **LURE**, release on **REST**, then press it once on **STRIKE**. Common fish forgive rough presentation; signatures need settled lure pulses.
5. Hold **Space** to reel during calm. Release on **DASH** and hold the displayed **A/D counter direction**. Tension at zero is safe; full tension breaks the line. All fish have readable, deterministic behavior.
6. Bring catches to **Fresh Catch**, the right-hand shop. **E** interacts nearby; **R** opens banking anywhere close to the harbor. Banking ends the expedition.
7. Three summer shore bream sell for 72 shells. The **65-shell skiff** is sold at **Tackle & Tide**, on the left. Board and disembark with **E** beside the long pier's berth.

## Controls

| Input | Action |
| --- | --- |
| WASD | Camera-relative walking; throttle/reverse and steering aboard |
| Shift | Run |
| Right mouse drag / arrow keys | Orbit camera |
| Wheel | Zoom |
| E | Shop, buyer, board or dock |
| F | Start expedition / cast from pier or boat |
| T / G | Tackle / presentation |
| Space | Place cast, hook, hold to present/reel |
| A / D during fight | Counter-steer the displayed pull |
| X | Abandon current cast; its bait remains spent |
| R | Bank near harbor |
| J / H | Catch notebook / field guide |
| Esc | Pause, settings, rescue, save and quit |
| F12 | Save a gameplay screenshot in the Godot user-data folder |

**Accessibility:** The pause menu offers toggle controls (tap instead of holding; tap again to release) and Focus pace (10% world speed, longer hook windows, and extended signature lure/dash cues). Directional controls latch independently, and clear when movement is locked. Focus pace changes timing, never rewards or unlock eligibility. Normal pace remains the default. Compact fishing instruments are the default; **Esc → On-screen guidance** adds current step instructions. The counter cue shows when your held or latched direction matches. Keyboard menus support Tab, arrows, and Enter.

## Expedition and progression

Each expedition starts with four minutes, eight free bait, and six catch slots. All menus pause daylight. A missed strike or broken line loses only that cast's bait. Sunset or calling rescue loses **all unbanked fish**, preserving shells, purchased equipment, boats, and permanent unlocks. New trips replenish daylight and bait without a fee.

Choose a temporary upgrade at departure and after every second catch. Silk leader reduces tension gain; Quick spool increases landing speed; Patient hook extends the hook window. Reed charm counters surge pressure, Picnic basket adds room, Golden hour extends daylight, and Bait tin provides three extra casts for an expanded creel. Repeated picks stack with limits on tension reduction. Balanced rods and woven creels are permanent shop purchases.

The shore stays useful: it offers reliable common fish and every signature species. The boat reaches richer populations quickly. Unlock the next coast by **banking** its predecessor's signature catch:

| Coast | Signature setup at the long pier or outer water | Distinct behavior |
| --- | --- | --- |
| Sunwake Harbor | Sunscale Mullet — Spinner + Twitch | Alternating weave, then one long dash |
| Jade Lagoon | Moonpetal Koi — Float + Drift | Announced feint before reversing its pull |
| Stormglass Reach | Stormglass Sailfish — Jig + Deep | Two runs separated by a short deceptive rest |

Autumn and winter replace the common shore and offshore populations, shorten calm intervals, and add faster pressure, shorter hook windows, seasonal lighting/weather, and +30% / +60% catch values. Each signature requires clean dash responses as well as landing progress; the tally is shown during the fight. Bank the Stormglass signature to complete the coast progression, then master harder seasons or build out your catch notebook.

## Saving

The game saves every five seconds and after catches, purchases, banking, rescue, and upgrade choices. `last_cast.json` uses a temporary file and rename. A continued expedition resumes safely at the harbor with remaining time, bait, upgrades, and unbanked catch. Boat owners return beside their skiff on the main pier. A cast interrupted by quitting is released; its spent bait stays spent. Fishing is never resumed halfway through a timed hook.

Godot stores saves, the local `voyage_log.jsonl`, and F12 screenshots in `user://`. On macOS that is:

```text
~/Library/Application Support/Godot/app_userdata/Last Cast/
```

To start fresh, quit and move `last_cast.json` somewhere safe. The game has no network calls or telemetry; voyage events remain local.

## Structure and provenance

- `scripts/main.gd`: expedition rules, shops, progression, save/load, interface and synthesized sound.
- `scripts/fishing.gd`: deterministic fishing state machine and fish definitions.
- `scripts/actor.gd`: walking, boat steering, collision-safe camera, line and fishing effects.
- `scripts/actor_visuals.gd`: authored procedural sailor and curved skiff meshes, articulated hand/foot targets, clothing detail, and animation.
- `scripts/fishing_hud.gd`: compact fishing instruments, physical cue projection, and optional guidance.
- `scripts/waterbed.gd`: sloping underwater terrain.
- `scripts/world.gd`: generated harbor, regional scenery, lighting and geometry batching.
- `shaders/`: procedural water, seabed, foliage, plaster, timber, terrain, roof and sky materials.

The requested `games/crazysora` was found as **`games/cozysora`**. Its project-owned primitive factories, material palettes, leaf generation, mesh batching, water noise, camera collision, and audio synthesis were inspected for techniques. Last Cast has its own implementations and no runtime dependency on Cozy Sora; the existing game was preserved. No external models, textures, images, animation, fonts, or audio files are bundled. Fonts use installed system fallbacks. The supplied fishing-boat image was used only for visual comparison.

See [FORWARD_PLUS_VERIFICATION.md](FORWARD_PLUS_VERIFICATION.md) for the Forward+ checkpoint: renderer decisions, matching views, independent reviews, measured performance, and unfinished fishing/save verification after the requested stop. [POLISH_VERIFICATION.md](POLISH_VERIFICATION.md) and [VERIFICATION.md](VERIFICATION.md) preserve the earlier Compatibility build records.
