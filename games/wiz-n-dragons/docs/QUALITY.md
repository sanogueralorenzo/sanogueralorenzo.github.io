# Verification

Build Debug and Release with `dotnet build` and `dotnet build -c Release`. For gameplay or visual changes, run `./run.command` and use ordinary controls. Keep checks focused; do not inject simulation state. F12 saves an unedited screenshot and paired telemetry.

## Verified baseline — 2026-09-09

Debug and Release builds passed with zero warnings/errors. Native checks used Godot 4.7.2 .NET, Forward+ / Metal on Apple M3 Max, with no observed runtime or shader errors.

- **Gameplay:** a short Ember flight covered camera following across encounter chunks, Fireball combat, the three-row spell menu, adding Arcane Orbs and resuming play.
- **Clouds:** a later visual check covered joined surfaces, pearl highlights and depth behind menus and during normal-speed flight.
- **Performance:** the initial light-load flight reported 8.35 ms mean frame time and 8.95 ms p99, with 25 encounter chunks and 54 cloud clusters. These measurements predate the current cloud geometry and are not a stress benchmark.

## Evidence

Each screenshot has a matching TXT capture in `evidence/`.

| Capture | Coverage |
| --- | --- |
| [First flight](../evidence/first-flight.png) | Initial flight and spell combat |
| [Spell menu](../evidence/spell-upgrade.png) | Three spell choices |
| [Runtime log](../evidence/first-flight-runtime.txt) | Initial gameplay telemetry |
| [Storybook clouds](../evidence/storybook-clouds.png) | Current cloud style |

Initial captures show earlier movement and art. Evidence from Boats 'n' Beasts does not verify this project.

## Coverage gaps

No full boss run, all-wizard/spell sweep, potion collection/revisit check or extended travel/stress test has been completed. Movement feel, click-to-stop overshoot, cloud-generation latency and current rendering performance need further play feedback.

Combat pacing and rewards remain inherited starting values. Floating-point precision at extreme coordinates and growing discovery/depletion records remain long-session limits.
