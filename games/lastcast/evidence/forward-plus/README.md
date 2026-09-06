# Forward+ evidence

Godot 4.7.2 on Apple M3 Max / 36 GiB unified memory / macOS 26.5.2; 1280×800 framebuffer, 60 Hz VSync. Before: Last Cast `647a6e8f7`, Compatibility/OpenGL. After: mandatory Forward+/native Metal.

## Matching gameplay views

Each `before-*.png` / `after-*.png` pair has adjacent JSON metadata. Camera transform, actor position, seed `41973`, region 0, summer, full daylight and framebuffer match exactly across all five pairs. These are lossless native readbacks from the same fixed 60 FPS visual replay of the existing walking, steering and orbit code.

| View | Before | After |
| --- | --- | --- |
| Shore | [PNG](before-shore.png) | [PNG](after-shore.png) |
| Walking | [PNG](before-walking.png) | [PNG](after-walking.png) |
| Boat | [PNG](before-boat.png) | [PNG](after-boat.png) |
| Sailing | [PNG](before-sailing.png) | [PNG](after-sailing.png) |
| Orbit / wake | [PNG](before-orbit.png) | [PNG](after-orbit.png) |

Video replay is separate from timing measurements. MovieWriter records fixed time steps; its encoding speed does not establish real-time FPS. Lossless PNGs are authoritative for small details such as the corrected white wake.

## Exploratory comparisons

`trial-sdfgi.png` shows the corrected static-occluder trial (energy 1.1). `trial-volumetric-fog.png` shows the rejected density 0.008 variant. `trial-msaa-orbit.png` and `trial-taa-orbit.png` sample camera orbits at 1.5 rad/s; their screenshot cadence varies with readback cost, so they demonstrate image sharpness, not frame pacing or exact frame correspondence. These variants predate final palette/wake tuning and are not shipped configurations.

## Measurements and ordinary play

Chronological frame samples, renderer logs, region/season checks and partial exported-app review are collected alongside this file. The user stopped the review during a real cast/presentation; hook/landing and save/relaunch remain unverified. Final video packaging and fishing screenshot re-review were not completed. The diagnostic scripts stay outside the project; no automated tests or benchmark scenes are shipped. See [the verification record](../../FORWARD_PLUS_VERIFICATION.md) for method, results and limitations. Previously earned progression used for the export review is explicitly imported, not claimed as reearned here.
