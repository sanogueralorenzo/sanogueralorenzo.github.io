# Finished implementation handoff

[OBJECTIVE.md](OBJECTIVE.md) records the agreed scope. [README.md](../README.md) documents launch, controls, boats, upgrades and ownership. [QUALITY.md](QUALITY.md) records completed live verification and its explicit limits; [evidence](../evidence/README.md) links the native captures.

The project is self-contained in `games/boats-n-beasts`. Development used the existing `/Users/mario/AndroidStudioProjects/boats-n-beasts-worktree`; no main-checkout edits or additional worktree were needed. Root AGENTS.md applies. The separate direction task provided read-only reviews; this task retained implementation ownership.

Godot 4.7.2 .NET, .NET 10 and the Compatibility renderer are required. `./run.command` builds, imports and launches. Use `GODOT_BIN` and `DOTNET_ROOT` to override the local toolchain locations. F12 captures the live viewport and telemetry for manual review.

Implemented: two boat abilities, six shared automatic weapons, simple weapon/stat upgrades, four ordinary enemies and a boss, seeded bounded ocean streaming with persistent depletion, frozen-combat fishing, harbor economy, victory and optional endless, defeat/retry and procedural animation. No external art, fonts, audio or automated tests are included. Runtime-generated creature strips and scenery textures are owned and bounded by their rendering nodes.

The user-selected progression stays simple: small varying rank/stat choices, obvious synergies and distinct boat abilities. Do not reintroduce prerequisite trees, catch equipment, unrequested currencies, or proprietary reference assets. Research inputs and partial reverse-engineering conclusions are documented in RESEARCH.md.

Latest user direction adds silver as a persistent balance, awarded on the next kill after a fresh random 45–90-second combat-time interval, with spending deferred. The existing voyage currency is now labeled gold. This supersedes earlier guidance against adding another currency.


Nautical gameplay pass: movement/boost and automatic encounter collection live in `VoyageMovement.cs`; weapon firing/projectiles in `VoyageWeapons.cs`. Bomb and Blast were replaced by Mines and Broadside without changing slot indices or the two-slot cap. Cannon ricochets and Harpoon pulls are automatic. `OceanWorld` now owns deterministic treasure/current/wreck placement and flow; `IsSolid` explicitly limits collision to islands, rocks and harbors. `SeaEncounters` draws encounter visuals, and scenery baking skips non-solids. Native F12 telemetry includes boost starts, current ride time, treasure/wreck counts and weapon behavior counters.


Readability polish: shared `UpgradeSymbol.DrawSymbol` renders cards, equipment badges and chart harbor categories. `Voyage.HarborOffers(Place)` is the single deterministic stock function for previews and purchases. Monster `Time` controls a 0.45-second emergence; enemy behavior waits for it, while the atlas fades/scales the creature through a ripple. Bulwark explanation is stored under `tutorial/bulwark_explained`; subsequent pulses retain their world effect. Native live verification covers boost depletion/recharge, equipment hover, repeated Bulwark pulses, emergence and both harbor categories; see the last QUALITY entry and `polish-*` evidence. Hover uses viewport input-event coordinates; equipment clicks do not sail.


Settings removal: controls are fixed to normal motion, hold-to-boost and manual fishing in a standard resizable window. No Settings screen or F11 handler remains. LoadProgress/SaveProgress retain the legacy user://settings.cfg filename for save compatibility, reading/writing only progression and the Bulwark tutorial flag; obsolete preferences are ignored and disappear on the next normal save.

Boat selection is now fixed at Voyage construction (get-only Boat property). Harbors have no boat-switch action; choosing a different boat starts a new voyage.


Run-flow simplification: dock automatically sells cargo; fishing resolves after one timed input with an eight-second timeout. Charts and return-to-harbor victory claim are removed; crossing three leagues spawns the boss and defeating it wins immediately. Right-click steering is removed. A full live run won immediately after the boss died (Trawler, Cannon rank 5, Whirlpool rank 1, Reload rank 1). Final-build native checks verified a one-reel catch, its automatic sale, no repeat sale on re-docking, and inert right-click. Capture reports include fishing cursor/target, last sale and boss flags.

Fishing results no longer open a menu: success and failure immediately return to sailing. A boat-following label shows the fish name/value (or “Got away”) for 2.5 seconds, rising gently and fading. Catches remain cargo until docking. Live success/failure, label disappearance and continued sailing verified; see catch-without-popup and sailing-after-catch evidence.

Catch storage is unlimited. Fishing eligibility depends on an available nearby school, never the number of held fish. No player-facing cargo counter or full-hold warning remains; docking still sells all held catches once. The native diagnostic capture retains its count for verification.

Boat abilities are now singular and explicit: Cutter has +65% firing rate only during boost, applied to cooldown progress so release ends the bonus immediately. Trawler releases a shot-clearing, enemy-pushing pulse every six sailing seconds, independent of movement, nearby enemies or safe waters. Pulse damage/soak and boost/slow-movement damage reductions are removed. Fishing and menus freeze the pulse timer with the simulation.

Weapon ranks each improve one property: Cannon +1 ball per shot, Harpoon +160 pull speed, Mines +30 blast radius, Lightning +1 target, Whirlpool +30 radius, Broadside +1 cannon per side. Weapon-rank damage and reload scaling are removed; cannon bounce count, harpoon piercing stays fixed. New-weapon cards describe acquisition; upgrade cards describe the next change. Boat stat upgrades remain single-stat choices.

Visual/sailing simplification pass: soaked and its slow/damage bonuses are gone. XP banks PendingUpgrades while sailing; docking sells catches and resolves free choices in sequence, then opens Harbor. Empty choice pools exchange each pending choice for 40 gold. Boats still have two weapon slots, and free choices reroll after each pick to respect capacity/max ranks. LVL turns gold while choices wait. World generation uses fewer/larger ordinary islands, clustered shore rocks, three procedural landmark styles and harbors every two chunks. Treasure/fish/wreck silhouettes are more distinct, hit particles shorter, friendly shots subdued, hostile shots on top. Boat cannon counts and attack visuals now follow ranks; WhirlpoolRadius is shared by simulation and rendering.

Boat lineup is now Gunboat (internal Cutter; starts Cannon), Aura (internal Trawler; starts Whirlpool) and Mage (starts Arcane Orbs). Broadside was removed and slot 5 now holds homing Arcane Orbs; there is no sideways target gate or volley. Mage has a violet roof/crystal and orbiting rank lights. Arcane upgrades add one orb per cast, with fixed damage/cadence; each orb steers toward the nearest live enemy within 650 units and collides with land normally. Existing two-slot limits and other boat abilities remain.
