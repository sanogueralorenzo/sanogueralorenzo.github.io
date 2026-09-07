# Source recovery and reuse

Recovery date: **7 September 2026**. All recovered material remains local. The public repository contains authored adapters, game rules, tooling, documentation, and source fingerprints only. The source games' licenses are not replaced by this repository's MIT license.

The source vault is `~/GameSourceVault/a-little-further`. `runtime/` is the restorable private runtime package; the other directories contain original downloads, decompilations, inventories, binary records, and recovery tools. `Local/` in the worktree is ignored by both Git and the Godot asset importer. Runtime loaders read the needed files directly.

## Sunwake

Source: [Sunwake — The Last Light](https://sunwake-the-last-light.openai.chatgpt.site/).

Downloaded the browser-delivered HTML, `assets/index-47cw1oNL.js` (1,258,282 bytes), its CSS, and `assets/boats/last-light-launch.glb` (919,720 bytes). The web reader could not open the site, but direct HTTPS downloads succeeded. The actual bundled JavaScript was formatted for inspection; this was not a visual-reference-only recreation.

Concrete reuse:

- The GLB is the runtime boat. Its geometry and material groups are retained, consolidated into 18 material groups. Authored mast, cloth sails, and a pirate pennant adapt it to this game.
- `Vg`, `Hg`, `Ug`, and `qg` supply the eight-component wave spectrum, directions, phases, amplitude relationships, and height sampling. CPU buoyancy and GPU displacement share these values. Amplitudes are reduced for sheltered island-scale waters.
- `pb.update`, `pb.sampleBuoyancy`, and `pb.terrainAvoidance` supply throttle inertia, velocity-dependent steering, lateral/longitudinal drag, four hull sample locations, spring response, and the three-point shore look-ahead.
- `Sh.update` supplies exponential chase-position and focus response, adapted to an elevated exploration camera.
- The ocean shaders' historical Kelvin-shoulder envelope, wake lifetime and distance rejection, diffuse facet modulation, chromatic axis, and crest absorption are translated into the private Godot water shader.

Private locations: `sunwake/readable.js`, `sunwake/camera.js`, `runtime/PrivateSources.cs`, `runtime/ocean.gdshader`, and `runtime/boat.glb`.

This is a selective translation of the sailing/rendering systems, not a port of Sunwake's game. Its lantern quest, weather-front system, hero-wave packets, persistent fluid interaction field, complete hull-exclusion profile, and full cinematic day/night system are not implemented. Lighting is retuned for the combined island art. No permissive license was established for the downloaded application assets, so they and the translated source stay private.

## Installed Steam SNØ

Source: `~/Library/Application Support/Steam/steamapps/common/SNØ/Sno.app/Contents/Resources/Data`.

Freshly decompiled the installed `Managed/Assembly-CSharp.dll` with ILSpy. Recovered types include `SGNoiseGenerator`, `MountainGenerator`, `MountainChunk`, `MountainChunkPool`, `DrawDistanceController`, `BiomeGenerator`, and `StudioGauntlet.MeshGeneration.ProceduralMeshGenerator`.

Concrete translations in the private engine-independent C# file:

- `SGNoiseGenerator.FractalNoise`: octave accumulation with lacunarity and persistence. Unity's seeded noise primitive is replaced explicitly with an authored smooth-value primitive; the original primitive is not claimed to be recovered.
- `MountainGenerator.GenerateMountainPositionsAndIndices`: a bordered sample grid supporting interior mesh construction and edge-normal sampling.
- `DrawDistanceController.UpdateDrawDistance`: conversion of draw distance to required neighbouring chunks.

The recovered generator's queued generation and chunk lifecycle informed the concrete bounded island-streaming adaptation. The game's nearest-first queue, island profiles, biome choices, obstacle layout, and origin-rebase policy are authored for the ocean; they are not represented as verbatim recovered SNØ implementations. `MountainChunkPool` itself was only an empty specialization of a generic object pool.

Private evidence: `sno/*.cs` and `sno/types.txt`. **The local SNØ port was not inspected or reused.** The existing .NET/ILSpy executables were reused as tools, not as game source.

## Installed Steam A Short Hike

Source: `~/Library/Application Support/Steam/steamapps/common/A Short Hike/AShortHike.app/Contents/Resources/Data`.

Recovered managed `Player`, `PhysicsMovement`, and `PlayerIKAnimator` code. UnityPy exported 290 meshes from `sharedassets2.assets`, selected additional meshes from `level2` and `sharedassets0.assets`, decoded scene transforms/material associations, extracted textures, and recovered animation-clip data. Its assets are the primary source of island scenery and captain/crew silhouettes.

Runtime selections include:

| Asset | Serialized file / path ID |
|---|---|
| Palm | `sharedassets2.assets` / 561 |
| Large pine | `sharedassets2.assets` / 633 |
| Birch | `sharedassets2.assets` / 589 |
| Bush | `sharedassets2.assets` / 559 |
| Coastal/land rocks | `sharedassets2.assets` / 593, 584, 585 |
| Captain/crew bird silhouette | `sharedassets0.assets` / 21 |
| Glide wings | `sharedassets2.assets` / 715 |
| Grass illustration | `sharedassets2.assets` / 322 |

The original palm orientation is applied before normalization. Geometry is rescaled and materials are harmonized into the game's palette. The extracted Grass texture is sampled on procedural island terrain.

Movement translates the desired-velocity response from `PhysicsMovement` and the jump grace, cooldown, hold-to-glide timing, terminal glide fall speed, and climbing/stamina concepts from `Player`. The original force-driven Rigidbody implementation is adapted into the engine-independent height-field controller.

`FlapWings` (`sharedassets1.assets` / 83) supplies actual streamed wing-scale key data for gliding. The decoded `PlayerIKAnimator.headBobCurve` supplies the body-bob Hermite curve. The clip data and curve are read from the private package. Other recovered clips, including `NPCWalkFast` and `ChestOpen`, are retained for inspection but **are not runtime animations**. Full humanoid skeletal/IK retargeting has not been performed; the current characters combine the selected recovered meshes/curves with authored pirate accessories and feedback animation.

Private evidence: `hike/Player.cs`, `hike/PhysicsMovement.cs`, `hike/PlayerIKAnimator.cs`, `hike/behaviours.json`, `hike/inventory.json`, extraction scripts, and runtime asset manifests. Inventory errors are retained in `hike/failures.json`; not every serialized behaviour was decoded.

## Installed Windows Megabonk

Source, exactly as requested: `~/Applications/Sikarugir/Windows Steam.app/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Megabonk`.

**Megabonk was not launched, played, reinstalled, or modified.** The installation uses IL2CPP. Il2CppDumper recovered metadata, native addresses, layouts, and dummy assemblies from `GameAssembly.dll` and `global-metadata.dat`. Its dummy C# method bodies are empty and are not treated as recovered implementations.

The general type-tree generator crashed on this build. A narrower binary recovery decoded 107 relevant records using the native type layouts. Selected `EnemyData` and `WeaponData` fields were decoded directly from serialized payloads, with the payload sizes and field offsets checked against the recovered layouts. The private `bonk.json` retains source names, asset-file IDs, and values.

Runtime data reuse:

- Sword, revolver, lightning, poison-flask, bow, and frost-walker damage/cooldown/burst/projectile data underpin captain and crew attacks.
- Skeleton and armored-skeleton health, damage, and speed underpin the two enemy classes, with explicit balance multipliers in `SourceTuning`.
- The revolver's projectile count and burst duration drive a timed multi-shot volley.
- `Ghost` mesh (`sharedassets1.assets` / 1843) and `Skull` (1858) are used for pirate monsters. The recovered renderer rotation offset, −90° on X, is applied before normalization.

Specific native-code recovery, independently disassembled with Capstone:

- `EnemyTargeting.GetClosestEnemy`, RVA **0x41C1E0**: the no-vision selection branch filters dead/dying candidates, computes squared center distance, skips candidates at or beyond the current best, and retains the closest candidate. This loop is translated into `PrivateSources.ClosestEnemy`; the core foe list and range replace Unity collider lookup/overlap queries, and positions use the ocean plane. The source raycast/vision branch and smart/random targeting are not ported.
- `EnemyWave.EnemiesPerSecond`, RVA **0x471CE0**: integer count converted to float and divided by spawn interval. This is translated and used for spawn pacing.
- `EnemyWave` constructor, RVA **0x471DA0**: wave duration/count/interval defaults recovered. Encounter pressure is scaled down for a small crew.
- `WeaponBase.IsCooldown`, RVA **0x431780**: the used-at time plus cooldown is compared with game time. This confirmed the timing gate; the game's timers implement the same gate semantics.
- `ItemGlovesLightning` constructor, RVA **0x459F90**: cooldown, damage multiplier, and radius constants are recovered and used in the adapted Stormcaller/Gunner trigger.

**Unrecovered material:** the complete native targeting, AI, item-proc, and hit-feedback implementations have not been reconstructed as source. Metadata/signatures alone do not count as that recovery. The nearest-target scan is a direct native-code translation as described above. Chase/telegraph resolution, damage presentation, and the four-berth crew rules are authored adaptations using the recovered data and specific routines above. The lightning trigger is deliberately adapted to crew synergy rather than presented as Megabonk's original item trigger.

Private evidence: `megabonk/raw-config.json`, `megabonk/decoded-config.json`, `megabonk/wave-disassembly.txt`, `megabonk/combat-disassembly.txt`, `megabonk/targeting-disassembly.txt`, `megabonk/asset-selection.log`, and `dumper/`. Recovery tools and failures remain alongside them.

## Other material and redistribution

CozySora assets/code were not used. The Last Cast was excluded. No external image generation was used. Pirate accessories, UI, progression rules, terrain profiles, input adapters, and procedural audio are authored for this project. The local Godot .NET application was copied into a separate development launcher so native testing would not target another project's open Godot editor.

[Source fingerprints](source-fingerprints.json) identify the exact downloaded/installed inputs without publishing them. The runtime package has its own per-file SHA-256 manifest, checked by `tools/verify-local.py`. Gameplay images/video also stay in the local vault because they depict recovered proprietary material.
