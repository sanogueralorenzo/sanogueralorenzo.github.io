# Boats ’n’ Beasts handoff

Direction B replaces the previous 2D art with native tactile procedural 3D. [ART_DIRECTION.md](ART_DIRECTION.md) is the current visual contract; [README.md](../README.md) covers launch, controls and gameplay. [QUALITY.md](QUALITY.md) and [native evidence](../evidence/README.md) distinguish current verification from historical builds.

## Runtime and ownership

Use Godot 4.7.2 .NET and .NET 10. `./run.command` builds, imports and launches Forward+; `GODOT_BIN` and `DOTNET_ROOT` override local toolchain paths. The reviewed machine used Metal on Apple M3 Max. The separate native art proof is `./run.command art-sample.tscn`; Tab changes inspection scale and F12 saves the viewport. It does not construct a Voyage.

Engine-independent simulation remains in `source/core`. `StartingArea.cs` now owns the fixed home geography shared by the title and gameplay; `OceanWorld` uses it for the central 3×3 chunks and retains seeded generation offshore. `Game.cs` owns input, menus, HUD, persistence and rendered-frame F12 captures. `OceanView3D` reads the Voyage, synchronizes native actors/scenery/effects and removes inactive resources. Starting from boat selection retains that preview voyage and all native resources; the input-transparent menu fades for 0.65 seconds while the boat follows a short, overridable initial course. The camera holds for 0.8 seconds before easing toward the boat. Menu-only object offsets are removed. `NativeStage3D` owns lighting, water and the shared camera projection/unprojection. Simulation `(x,y)` maps to native `(x/100,0,y/100)`; bows point along -Z. Scale remains 0.74 with 0.84 ground-plane foreshortening.

`EnvironmentArt3D` generates sand, broad beveled rock masses, submerged cove stones, cottages and vegetation. `ActorArt3D`, `ActorGeometry` and `ActorEquipment3D` generate boats, six weapon fittings and all five monster forms. `Effects3D`/`EffectsGeometry` own position histories, foam, submerged fish and encounter/weapon effects. Shared shaders provide matte grain, water, shallow depth and subtle creature animation. Old 2D world renderers/caches were removed. Every world asset is reproducible from C# and shaders; no external models, textures, image-generated gameplay art, GDScript or audio were added.

## Preserved scope

Gunboat starts Cannon and fires 65% faster while boosting; Aura starts Whirlpool and periodically clears shots/pushes enemies; Mage starts homing Arcane Orbs. There are two total weapon slots including the starter. Each harbor has three stable offers from one category, each upgrade has one benefit, and free level-up choices immediately freeze combat at sea and resume sailing after selection.

Schools allow one cast, results return directly to sailing, catches have no capacity limit and sell automatically on docking. Gold is voyage-local; scarce randomized silver persists. No settings, seed UI, mid-voyage boat switching, Soaked, new progression systems or audio expansion were introduced. Keep the existing boss victory/endless and defeat/retry flow. Save compatibility retains the existing `user://settings.cfg` progression storage.

## Verification and continuation

The shared-start follow-up verified all three previews/departures, fixed geometry across fresh seeds and retry, unchanged camera during the fade, click override before fade completion, normal combat/level-up, real home docking, shore collision and returning to the title. The current QUALITY entry and `departure-*` evidence distinguish this focused pass from the broader renderer verification below.

Native play covers all three boats, movement/held boost/release, combat, manual fishing success/miss/timeout, automatic sale/redock, paid harbor upgrade, free level-up freeze/resume and streaming. Debug/Release pass. Current native logs are clean. Sustained reviewed runs support 60 FPS on the M3 Max; the quality record includes precise measurements and limitations, including no fresh final-renderer boss victory or extreme endless crowd run.

Development and final integration used `/Users/mario/AndroidStudioProjects/boats-n-beasts-worktree`. Three workers used isolated local branches for environment, actors, and effects/independent critique; main alone controlled native runtime, reviewed integration and delivered to main. No PRs or automated tests. Preserve unrelated repository work, follow root AGENTS.md, and consult current art/quality documents before revising this presentation.
