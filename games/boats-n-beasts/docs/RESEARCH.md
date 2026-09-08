# Research provenance

All game logic and visuals in Boats n Beasts are original implementations. The reference image informed the bright, shaded near-overhead presentation, spacious ocean and readable HUD; it is not bundled or loaded by the game.

## Sno

Read the requested local `sno-godot-local/scripts/main.gd` and `source/runtime/TerrainCore.cs`, `ObstaclePlacementCore.cs`, and `PopulationCore.cs`. Useful concepts were deterministic local randomness, bounded placement attempts, edge clearance, separate placement/population decisions, and explicit chunk load/unload ownership. Boats n Beasts does not import those files or their engine dependencies. Its regular edge lanes, seed-coordinate hash and sparse depletion map are custom.

## Megabonk

The supplied `dumper/dump.cs` identifies StageSummoner methods `GetBaseCreditsPerSecondUncapped` (RVA 0x486180), `GetBaseCreditsPerSecond` (0x486210), and `GetNumTargetEnemies` (0x4862E0). The read-only installed-binary excerpts in `megabonk-spawning-disassembly.txt` show uncapped credits using a factor proportional to `1 + stageTimer / 60 * 0.5`, and target-count arithmetic `5 + 200 * clamp01(stageTimer / duration)`, followed by additional multipliers. The denominator field at offset 0xA4 and all multipliers have not been fully provenance-resolved. This is partial arithmetic recovery, not a complete reconstruction or a claim that every version behaves identically.

The old EnemyWave `minNumEnemies / spawnInterval` method is separate from this newer credit summoner. Boats n Beasts borrows the separation of income, population target, and pacing; all its distance thresholds, caps, spawn rates, enemy selection, boss escorts and balance numbers are custom.

## Nova Drift demo

The separate direction review inspected the supplied local demo's `localization.csv`, `prefabplayerbuilds.csv`, and `prefabplayerbuildssnippets.txt`. Readable descriptions establish varied weapon/body/shield combinations and behavior-changing upgrades. The compiled FORM package has no CODE chunk; movement/combat source and numerical tuning were not recovered. No proprietary assets or code were copied.

The user's later direction supersedes complex progression proposals: use simple Megabonk-like weapon/stat choices, with ranged, aura and close attacks accessible to every boat. Nova Drift remains a reference for satisfying combat and readability, not a specification for a prerequisite tree.

## Silver reward follow-up

Inspected the supplied IL2CPP metadata and the installed GameAssembly.dll, not recovered C# method bodies (dump.cs contains stubs). `MoneyUtility.CheckSilver` (RVA 0x469230), also inlined in `OnEnemyDied` (0x46A1E0), compares `MyTime.time` against `nextSilverSpawnTime` and calls `SpawnSilver(enemy)` after the threshold. `script.json` resolves the static type pointers; dump.cs resolves MyTime.time at offset 0x4 and the next-spawn field at offset 0x8.

The tail of `SpawnSilver` (0x46B070) reads stat 49 (`SilverIncreaseMultiplier`), divides the verified float constant 60.0 by it, and writes `MyTime.time + interval` as the next spawn time. Thus this installed version’s ordinary enemy-death silver path is time-gated, not every N kills and not a Bernoulli roll on every kill. Other sources exist (`SpawnSilverNoTimerImpact`); their full reward behavior and the initial/static timer setup are outside this finding. Exact excerpts and binary hash are in [megabonk-silver-disassembly.txt](megabonk-silver-disassembly.txt).

Boats n Beasts adapts that gate with an original uniform random 45–90 combat-second interval, including the first award. The next kill after eligibility awards one silver, then starts a fresh interval from that award. No catch-up drops accumulate during idle time. Silver randomness has its own per-voyage stream and does not alter seeded geography, combat, upgrades or fishing. The random interval is the user-requested adaptation, not a claim about Megabonk’s recovered code.
