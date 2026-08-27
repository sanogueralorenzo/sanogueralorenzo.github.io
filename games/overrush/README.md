# Overrush

Early movement-survivor prototype for fast combat runs across large procedural landscapes.

## Current scope

- A newly randomized 3.2 km × 3.2 km terrain on every run.
- A route graph generated before the terrain, with occasional alternate paths that split and merge.
- Authored terrain features: broad valleys, banked turns, gradual launch hills, smooth landing zones, and gently shouldered narrow passes.
- Three blended regions per run: Verdant Reach, Ember Basin, and Prism Highlands.
- Original rock spires, boulder fields, distant ridges, and procedural materials.
- Route geometry designed to preserve readable 200–400 meter sightlines at high speed.
- Packed Z-bucket route lookups and heightmap collision keep full world generation responsive.
- A small auto-running ball and follow camera used to test terrain flow, scale, and high-speed traversal.
- A short, hold-sensitive dash that is repeatable on the ground, available once per airtime, and provides a reliable 0.14-second base dodge window; Dashbreaker's Phase Shell extends that protection.
- A speed-aware perimeter jetstream that smoothly banks traversal back across the landscape instead of using invisible walls or abrupt terrain obstructions.
- Momentum-preserving steering and glancing collision response prevent high-speed turns or scenery contact from stopping the run.
- Five phase-gated regular roles create escalating traversal decisions: Pursuers close space, Skimmers intercept, Bulwarks deny an area, Rift Weavers mark the runner's projected route, and Swarm Foundries multiply if ignored.
- Fragile zero-reward Foundry drones add bounded pack pressure without creating an experience exploit or exceeding the global population cap.
- Charges, pulses, remote blasts, and reinforcement blooms use distinct ground telegraphs before their active windows; scheduled elites amplify four different roles without removing the warning, and specialist body overlap is deliberately weaker than each role's signature attack.
- A homing arc weapon, collectible experience, integrity damage, run timer, and defeat state.
- Value-tiered crystal cores latch once approached, overtake maximum dash speed, and recover from distant terrain so fast traversal never discards earned progression or accumulates stale rewards.
- Distinct coral integrity cores add a bounded recovery economy: a 14-point core is earned every eighteen rewarding defeats, elite cores repair 30, no more than three may wait in the world, and full-health runners bank rather than waste them.
- A first level-up commitment to one exclusive movement-centric engine: Dashbreaker, Stormtrail, or Arcstorm.
- Path-specific follow-ups create different combat geometry: charged dash-entry and unconditional exit detonations, persistent traversal wakes, or speed-scaled multi-target chain arcs.
- Each mature engine forks into one of two exclusive evolutions: impact or gravity dashes, parallel or repeating wakes, and aimed lances or close-range electrical orbits.
- Late Slipstream ranks gain damage and width with diminishing returns; mature Twin Current lanes space their wake samples farther apart, while Tempest Anchors cap their footprint and lifetime and share a per-target pulse interval so dense Overrun packs cannot feed automatic map-wide clear loops.
- Ramjet checks a bounded swept dash corridor rather than a single frame position, preserving direct-impact reliability at maximum speed without allowing teleports or discontinuities to register as hits.
- Every evolution has a capped three-rank support upgrade, keeping late-run choices transformative while preserving each branch's traversal-driven identity.
- Mature evolved builds make a second protected commitment to one of three Drive Catalysts: Redline rewards dash velocity, Airframe rewards airtime, and Pulse rewards deliberate dash-timed attack windows.
- Every evolved engine also chooses an independent arsenal: Hunter Array missiles cover distant targets, Drift Blades reward close pack threading, and Backdraft Mine turns dash exits into delayed pursuit traps; each has a dedicated three-rank support upgrade.
- Every catalyst carries visible downtime penalties and combines with all six evolution geometries and three arsenals for 54 endgame playstyles; arsenal damage and empowered catalyst uptime remain visible in the run recap for balance review.
- Each run grants three honest rerolls and one deliberate banish: rerolls only spend when a different offer exists, while banishment permanently removes one standard upgrade without consuming the level.
- Every draft card identifies its strategic category, path color, next rank, and exact mechanical result; catalyst cards give their downtime penalty equal prominence instead of hiding it in flavor text.
- Keystone commitments and exclusive evolution forks cannot be banished, and universal Kinetic Repair caps at three ranks instead of becoming an unlimited dominant fallback.
- A structured 20-minute run: Breakaway, Pressure Rises, Redline, Overrun, and a two-minute, seed-selected Apex climax with explicit victory or deadline failure.
- The live HUD counts down to the Apex, then switches to its two-minute defeat deadline; reproducible seed information remains available from pause without competing with the immediate objective.
- Authored build-cadence windows stage the engine, evolution, arsenal, and Drive decisions across the run; rank-qualified forks remain protected until their intended beats, so faster pickup recovery cannot collapse the full identity into the opening minutes.
- Strategy-aware seven- and eighteen-minute balance soaks cover all six evolution branches inside overlapping early and late clear envelopes while rejecting stalled traversal. Their routes exercise distinct execution: setup dashes, direct Ramjet impacts, woven Twin Current lanes, bounded Tempest zones, aimed Storm Lances, and close Arc Orbit threading.
- Two named Apex encounters demand different traversal: the Velocity Reaver commits to charges and body-centered pulses, while the Rift Matriarch predicts the route and releases bounded, zero-reward broods.
- Both Apex encounters visibly escalate below half health with faster pursuit or shorter route-denial cycles, distinct curved silhouettes, warning tones, arrival banners, boss HUD labels, and recap identity.
- A run-launch screen summarizes persistent Momentum, completed runs, victories, best survival time, and the selected challenge protocol.
- Framed victory and defeat recaps identify the build, arsenal, catalyst execution, upgrade count, phase, clears, elites, actual damage contribution, incoming damage by attack source, applied integrity recovery, distance, peak speed, dashes, rewards, unlocks, and personal records before retrying.
- Run endings are atomic: victory, deadline, or integrity failure invalidates any in-flight draft and rejects late pickups or stale upgrade input before the recap is recorded.
- Victory and defeat recaps ask one optional “Would you run again?” question without stealing retry focus; the response is attached to that run's full telemetry and recent Yes sentiment appears on the next launch screen for playtest review.
- Recovery-safe, versioned profile saving keeps a previous valid backup, restores it if the primary save is missing or corrupt, and retains a bounded last-run snapshot plus personal clear, damage, and distance records.
- A bounded 20-run history preserves sanitized build outcomes for balance review; the launch screen summarizes recent form rather than letting one exceptional run hide a weak build.
- Timestamped draft telemetry and the outcome recap expose when each run's engine, evolution, arsenal, and Drive came online, supporting repeated pacing analysis instead of relying on final level alone.
- Twelve non-power masteries track first Apex clears across all evolutions, arsenals, and Drive Catalysts, then point toward the next unexplored clear to encourage experimentation without replacing skill.
- Momentum unlocks optional run protocols rather than permanent combat power: denser Redline spawns, high-risk Glass Velocity damage, and elite-heavy hunts each trade added pressure for larger rewards.
- Persistent comfort options provide a steady dash camera, reduced dash particles and combat flashes, and high-contrast attack zones with bright geometric boundaries while preserving directional damage information.
- Short first-run prompts teach steering, dashing, hopping, automatic combat, pickups, attack-zone reading, build structure, and the Apex win condition during live play; they retire automatically and can be disabled or replayed.
- An original procedural soundtrack layers an atmospheric velocity bed with a rhythmic drive that intensifies through Breakaway, Pressure, Redline, Overrun, and the Apex.
- Pooled synthesized cues distinguish dashing, damage, weapon impacts, attack warnings, enemy defeats, experience and integrity pickups, level-ups, phase changes, victory, and failure without importing placeholder audio.
- Persistent master, music, and independent effects mix controls apply immediately to active pooled players; outcome cues duck the run music so the ending remains legible.
- Full keyboard and gamepad action mapping supports analog steering, contextual prompts, controller-focused menus, and controller draft shortcuts without requiring project-level input configuration.
- A run-safe pause menu exposes live build context, immediate accessibility and audio changes, focused resume controls, and a two-step restart confirmation; victory and defeat provide focused retry buttons.
- The pause menu doubles as a compact loadout inspector, listing the current engine, evolution, Drive Catalyst, and every owned upgrade rank without interrupting or ending the run.

This is not yet the complete target game. The 20-minute structure, two Apex encounters, six build evolutions with three independent arsenals and three cross-engine catalysts, five-role enemy roster, measured run recaps, initial progression loop, onboarding, comfort settings, and audio foundation now exist, but broader content variety, deeper accessibility, repeated balance work, usability validation, and external playtesting remain long-term work.

## Generation architecture

- `route_generator.gd` owns deterministic route topology and authored feature samples.
- `route_lookup.gd` converts route samples into packed Z buckets for allocation-free height queries.
- `terrain_grammar.gd` owns noise, regional blending, and route-shaped terrain heights.
- `terrain_validator.gd` keeps test-only safety checks out of runtime generation code.
- `combat_director.gd` owns phase-weighted enemy composition, bounded reinforcements, spawning, escalation, targeting, deterministic experience and integrity rewards, and the distinct geometry of movement-triggered combat effects.
- `experience_pickup.gd` owns high-speed pursuit, stale-reward recovery, distinct experience/integrity silhouettes, and full-integrity banking behavior.
- `enemy_agent.gd` owns role stats, standoff/chase movement, telegraph state, attack resolution, rank treatment, and curved procedural silhouettes.
- `run_build.gd` owns testable experience thresholds, exclusive upgrade pools, evolution and catalyst forks, movement-conditioned output, capped support ranks, banishment filtering, alternate-offer detection, branch tuning, exact draft previews, and compact loadout summaries.
- `run_stats.gd` owns outgoing and incoming attack attribution, applied integrity recovery, catalyst uptime, traversal evidence, encounter and choice history, top-source ranking, and bounded recap snapshots.
- `run_pacing.gd` owns the deterministic phase, elite, Apex, deadline, and earliest protected build-fork beats independently of frame rate.
- `apex_catalog.gd` owns deterministic encounter selection, names, phase messaging, and shared boss tuning while `enemy_agent.gd` owns the distinct pursuit and route-denial behaviors.
- `run_protocols.gd` is the single catalog for challenge tradeoffs, reward multipliers, and Momentum thresholds.
- `progress_profile.gd` owns versioned progression state, deterministic run rewards, bounded run history, optional replay-intent feedback, non-power build mastery, protocol selection, atomic writes, and backup recovery.
- `run_onboarding.gd` owns the input-aware, time-bounded first-run guidance sequence independently of the HUD.
- `audio_director.gd` synthesizes and pools the original music and feedback palette, controls phase intensity, rate-limits warnings, and owns runtime mixing.
- `input_bindings.gd` owns the idempotent keyboard/gamepad action map and input-device detection used by movement, menus, prompts, and tests.

## Controls

- `A` / `D` or left / right: steer
- `W` or up: boost
- `S` or down: brake
- `Space`: hop
- `Shift` or `Alt`: dash (tap for a short burst, hold for maximum distance)
- `Escape`: pause or return from settings; restarting an active run requires confirmation in the pause menu
- `1` / `2` / `3` or mouse: choose a level-up upgrade
- `Q` during a level-up: spend a reroll when the active pool can produce a different offer
- `B` during a level-up: enter banish mode, then choose a removable standard upgrade with `1` / `2` / `3` or the mouse
- At the launch screen, `A` / `D` or left / right changes protocol and `Enter` / `Space` starts the run
- `Accessibility & Guidance` on the launch screen changes persistent comfort and audio preferences without affecting difficulty or rewards
- Gamepad: left stick steers, boosts, and brakes; `A` hops or confirms; `LB` / `RB` dashes; D-pad changes protocol; `Y` rerolls; `X` enters banish mode; Start pauses
- `R` retries only after a victory or defeat

## Map validation

Run the deterministic 20-seed terrain and formation gate with:

```sh
godot --headless --path games/overrush --script res://tests/validate_worlds.gd
```

The gate checks required terrain shapes, route continuity and slopes, local corridor gradients, sightline curvature, alternate-route frequency, formation clearance, finite terrain heights, three-region coverage, and layout uniqueness.

Run the deterministic regular/alternate generation performance gate with:

```sh
godot --headless --path games/overrush --script res://tests/benchmark_generation.gd
```

The current development-machine target is less than two seconds for a complete 321 × 321 world.

Run the terrain collision and grounded-runner integration check with:

```sh
godot --headless --path games/overrush --script res://tests/validate_heightmap_collision.gd
```

Run the dash timing and ground/air reset checks with:

```sh
godot --headless --path games/overrush --script res://tests/test_dash_state.gd
```

Run the build rules and playable combat integration checks with:

```sh
godot --headless --path games/overrush --script res://tests/test_run_build.gd
godot --headless --path games/overrush --script res://tests/test_build_evolution_balance.gd
godot --headless --path games/overrush --script res://tests/test_run_stats.gd
godot --headless --path games/overrush --script res://tests/validate_combat_slice.gd
godot --headless --path games/overrush --script res://tests/validate_build_paths.gd
godot --headless --path games/overrush --script res://tests/validate_enemy_roster.gd
godot --headless --path games/overrush --script res://tests/validate_draft_agency.gd
godot --headless --path games/overrush --script res://tests/validate_drive_catalysts.gd
godot --headless --path games/overrush --script res://tests/validate_arsenal_weapons.gd
godot --headless --path games/overrush --script res://tests/validate_apex_variants.gd
godot --headless --path games/overrush --script res://tests/validate_run_recap.gd
```

Run the simulated 20-minute and in-engine maximum-speed boundary traversal checks with:

```sh
godot --headless --path games/overrush --script res://tests/test_boundary_current.gd
godot --headless --path games/overrush --script res://tests/validate_boundary_runtime.gd
```

Run the timed phase model and accelerated elite/Apex outcome checks with:

```sh
godot --headless --path games/overrush --script res://tests/test_run_pacing.gd
godot --headless --path games/overrush --script res://tests/validate_run_climax.gd
```

Run the persistent-profile and challenge-protocol checks with:

```sh
godot --headless --path games/overrush --script res://tests/test_progress_profile.gd
godot --headless --path games/overrush --script res://tests/validate_run_protocols.gd
godot --headless --path games/overrush --script res://tests/validate_accessibility.gd
godot --headless --path games/overrush --script res://tests/test_input_bindings.gd
godot --headless --path games/overrush --script res://tests/validate_controller_pause.gd
```

Run the waveform headroom/performance and gameplay-audio connection checks with:

```sh
godot --headless --path games/overrush --script res://tests/test_audio_synthesis.gd
godot --headless --path games/overrush --script res://tests/validate_audio_runtime.gd
```

Run the directional hit, numeric integrity, and unobtrusive recovery feedback check with:

```sh
godot --headless --path games/overrush --script res://tests/validate_damage_feedback.gd
```

Run the dash-speed pickup pursuit, stale-reward recovery, integrity-core cadence/banking, value-silhouette, and empty-drop check with:

```sh
godot --headless --path games/overrush --script res://tests/validate_pickup_flow.gd
```

Run the accelerated fixed-seed full-system progression cadence gate with:

```sh
godot --headless --path games/overrush --script res://tests/validate_progression_cadence.gd
```

Run the fixed-seed, strategy-aware seven-minute engine balance gates sequentially with:

```sh
godot --headless --fixed-fps 300 --path games/overrush --script res://tests/audit_engine_soak.gd -- dashbreaker 41001
godot --headless --fixed-fps 300 --path games/overrush --script res://tests/audit_engine_soak.gd -- ramjet 41001
godot --headless --fixed-fps 300 --path games/overrush --script res://tests/audit_engine_soak.gd -- stormtrail 41001
godot --headless --fixed-fps 300 --path games/overrush --script res://tests/audit_engine_soak.gd -- tempest_anchor 41001
godot --headless --fixed-fps 300 --path games/overrush --script res://tests/audit_engine_soak.gd -- arcstorm 41001
godot --headless --fixed-fps 300 --path games/overrush --script res://tests/audit_engine_soak.gd -- arc_orbit 41001
```

Each gate requires at least 20 km of traversal, a viable clear envelope, the intended evolution and arsenal, and source-share guardrails where a single effect could otherwise erase the build's decision-making.

Repeat the same six commands with `1080` as a third user argument for the 18-minute Overrun sample, for example:

```sh
godot --headless --fixed-fps 300 --path games/overrush --script res://tests/audit_engine_soak.gd -- stormtrail 41001 1080
```

The late gate requires every engine to complete its evolution, arsenal, and catalyst on schedule, traverse at least 48.6 km, remain inside the shared 500–1,000 clear envelope, and preserve measurable contributions outside its leading effect.

Run the fixed-step, finite-integrity 20-minute survival budget audit with:

```sh
godot --headless --fixed-fps 300 --path games/overrush --script res://tests/audit_survival_soak.gd -- 41001
```

The audit uses a threat-aware Arcstorm route plus a controlled execution mistake every 45 seconds. It requires the real enemy population, pickups, recovery cap, build cadence, traversal, Apex phase, and victory/deadline resolution to sustain one complete run. Controlled mistakes make the recovery budget reproducible; this is a balance guardrail, not a substitute for human playtesting.
