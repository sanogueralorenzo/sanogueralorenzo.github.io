# AEOLIAN — concise game design

Last reviewed: 2026-08-23 · Owner: product/design · Status: preproduction baseline

## Promise and boundaries

AEOLIAN is a single-player, 10–15 minute downhill roguelite for PC. The player
carves through a mountain rebuilt from a deterministic seed, choosing between
safer lines and faster or more rewarding routes while preserving momentum and
surviving to the base.

The smallest release has three mechanically distinct biomes, one readable run
structure, a restrained pool of run upgrades, and excellent movement. It has no
combat, multiplayer, open world, NPC simulation, large inventory, live service,
or user-generated terrain. Stormpeak, ghosts, leaderboards, daily seeds,
achievements, and platform services remain outside the active scope.

## Player fantasy and design pillars

The player rides a fictional **windboard**: one piece of equipment that can
plough powder, skim sand, and surf ash without separate locomotion systems. It
supports a slightly supernatural relationship with wind while keeping the
controls grounded and readable.

1. **Satisfying descent.** Traversal is the game; acceleration, carving,
   takeoff, landing, camera, sound, and terrain response receive priority.
2. **A changing mountain.** Authored pieces and controlled rules create new,
   reproducible route decisions—not arbitrary noise.
3. **Biomes change play.** Grip, momentum, sight lines, wind, hazards, and sound
   change with the surface.
4. **Relaxing but addictive.** Broad readable lines create flow; optional risks,
   near misses, speed, and scarce recovery create tension; restart is immediate.
5. **Small but polished.** New systems must deepen a pillar and fit production,
   test, performance, and maintenance budgets.

## Run structure

Target duration is 12 minutes (acceptable full-run band: 10–15 minutes).

1. Launch to title; choose New Descent, Continue (when valid), or enter a seed.
2. A short summit presentation reveals the seed and teaches/reinforces controls.
3. Descend **Frost → Dunes → Ashlands**. The macro-order is fixed for pacing and
   visual logic; chunks, branches, hazards, rewards, weather, and modifiers vary.
4. Each biome targets 3–4 minutes and contains at least two meaningful forks.
5. Safe routes preserve survival; risky routes offer speed, score, wind shards,
   or a better upgrade choice.
6. A brief sheltered transition between biomes offers one of three upgrades.
7. A run ends on a terminal crash or reaching the mountain base.
8. Results explain time, score, route, cause of failure, discoveries, and unlocks;
   retrying the same seed or starting a new one takes at most two actions.

Pausing is allowed outside terminal crash presentation. Quitting during a run
stores a resumable checkpoint at the most recent biome transition—not an exact
mid-slope state—to keep saves robust and prevent reroll abuse.

## Movement and controls

The controller is gravity-led and momentum-respecting, with tuned assistance
that prevents the board from feeling like a frictionless physics prop.

| Intent | Gamepad | Keyboard | Result |
| --- | --- | --- | --- |
| Carve | Left stick | A/D or arrows | Turns across fall line; harder carve sheds speed |
| Tuck | Right trigger | W/Up | Smaller turns, lower drag, greater risk |
| Brake | Left trigger | S/Down | Strong carve/skid; speed and stability cost |
| Jump / recover | South face | Space | Ollie while grounded; brace/reorient in air |
| Air steer | Left stick | A/D or arrows | Limited yaw/roll correction |
| Look back / free look | Right stick | Mouse | Optional camera influence, never required |
| Pause | Menu | Escape | Pauses simulation and opens settings |

Keyboard input is digital but filtered into steering smoothly. Gamepad deadzone,
sensitivity, inversion, and vibration are configurable. All gameplay and menu
actions must be remappable before UX gate approval.

### Stability, landing, and crashes

- Terrain contact builds a stable surface frame; brief contact loss on rough
  ground does not become an arbitrary jump.
- Harsh lateral impacts, extreme misaligned landings, sustained unstable posture,
  or explicit lethal hazards cause a crash. Speed alone never does.
- Low-severity mistakes wobble, scrub momentum, and allow player recovery.
- Base rules provide no lives. A clearly telegraphed **Gale Guard** upgrade can
  convert one otherwise-terminal crash into a large speed loss and short recovery.
- Crash-to-retry target is under 3 seconds, with an optional short recap only if
  it never delays input.

Tricks are not a release system. Airtime, clean landings, near misses, and route
risk may score, but there is no rotation combo, grab, or trick inventory. Revisit
only after the complete run is balanced and movement is not compromised.

## Biome gameplay

| Biome | Handling and visibility | Signature decisions | Minimum release hazards |
| --- | --- | --- | --- |
| Frost | Powder is forgiving but slow; hardpack is quick; ice has low lateral grip; fog/snow reduces preview | Stable powder versus fast ice; shelf shortcuts versus avalanche exposure | Avalanche lane, breakable snow shelf, frozen-lake weak ice |
| Dunes | Loose sand drains momentum; compact ridges carry speed; tailwind adds acceleration; sandstorm occludes distant lines | Spend speed climbing a safe ridge or dive into unknown bowls; follow gusts for risky boosts | Sinkhole, shifting dune face, buried-ruin collision |
| Ashlands | Ash is neutral but unstable; brittle crust fails after loading; heat reduces safe line width; smoke pulses visibility | Commit across collapsing crust or route around vents; use vent lift versus falling-rock risk | Vent, brittle crust, falling rock / heated zone |

Each biome requires its own surface mix, route grammar, hazard family, sound bed,
weather behavior, landmark language, and tuned difficulty curve. Palette alone is
never sufficient.

## Rewards, upgrades, and scoring

Wind shards placed on exposed, technically demanding lines contribute score and
limited unlock progress. Each transition presents three run upgrades from a
seeded pool. Initial upgrade archetypes are:

- **Edge control:** grip versus maximum carve-speed tradeoff.
- **Momentum:** higher terminal speed with reduced landing forgiveness.
- **Aerial:** stronger jump and air control, but weaker rough-ground stability.
- **Terrain affinity:** resistance to one surface family; never universal immunity.
- **Wind rider:** stronger benefit and stronger penalty from wind direction.
- **Gale Guard:** one crash recovery, with no performance bonus.

Upgrades use additive/multiplicative modifiers with explicit caps and conflict
tags. No upgrade invalidates a hazard or makes the optimal route automatic.

Score communicates mastery but does not gate completion: descent progress,
remaining momentum, risky-route shards, near misses, clean airtime/landings, and
finish time contribute. A breakdown is always visible at results.

Meta-progression unlocks sidegrade upgrades and cosmetic board trails through
clear milestones. It never grants permanent speed, grip, lives, or damage
reduction. All movement-essential options are available from the first run.

## Art, audio, and narrative direction

Art is stylized, windswept, and graphic: large faceted terrain forms, restrained
surface palettes, high-contrast route silhouettes, and ribbon-like wind VFX.
The rider and board use a readable dark silhouette with one warm accent. Geometry
and lighting—not high-frequency textures—carry the environment at speed.

Audio is sparse and physical. Wind, board/surface contact, speed, and landing
layers form the primary score; music grows at route commitments and biome peaks,
then breathes at shelters. No dialogue is planned. Minimal environmental motifs
suggest an impossible recurring mountain without starting a narrative campaign.

## Onboarding and accessibility baseline

The opening Frost terrain teaches carving, tucking, braking, and one jump through
wide, low-consequence shapes and short prompts. Prompts adapt to the active input
device and can be reviewed or disabled.

Release baseline: full remapping, keyboard-only and controller-only navigation,
adjustable sensitivity/deadzone/vibration, reduced shake, reduced speed-line VFX,
camera distance and look-ahead choices, independent audio buses, scalable UI,
non-color-only hazard/reward communication, pause-anywhere support, and readable
text. Subtitle UI is required only if voiced language is later added.

