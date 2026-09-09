# Verification

Build Debug and Release with `dotnet build` and `dotnet build -c Release`. For gameplay changes use `./run.command` and ordinary controls. Keep verification focused; do not inject simulation state. F12 saves unedited native screenshots with telemetry.

## Initial port — 2026-09-09

Debug and Release passed with zero warnings/errors. Godot 4.7.2 .NET launched using Forward+ / Metal on Apple M3 Max without observed runtime errors.

A short Ember flight checked camera-follow movement across multiple encounter chunks, layered cloud scenery, automatic Fireball combat, the three-row spell upgrade menu, adding Arcane Orbs and resuming play. At the final capture, position was approximately (2468, 1217), with 25 active encounter chunks, 54 cached cloud clusters and four visible pickup nodes. Level 2 had Fireball and Arcane Orbs equipped, with two recorded Arcane casts. Mean frame time was 8.35 ms and p99 8.95 ms during this light-load session; it is not a stress benchmark.

Evidence: [flight](../evidence/first-flight.png), [spell menu](../evidence/spell-upgrade.png), matching TXT captures, and [runtime log](../evidence/first-flight-runtime.txt). Captures precede only final wording, internal naming and potion particle-color cleanup.

## Limits

This is a first playable adaptation, not a finished art or balance pass. No full boss run, all-wizard/spell sweep, potion collection/revisit run or extended travel/stress test was performed. Combat pacing and rewards are inherited starting values. Floating-point precision at extreme coordinates and indefinitely growing discovery/depletion records remain long-session limits. Historical Boats 'n' Beasts evidence and ocean-only samples are kept in the original project rather than presented as verification of this game.
