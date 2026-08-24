# Technical design

Last reviewed: 2026-08-23 · Owner: engineering · Status: approved Phase 0 direction

## Baseline and principles

- Godot 4.7.2 stable (pinned for initial production), GDScript, Forward+ renderer,
  Jolt Physics. Engine upgrades require a recorded decision and the full relevant
  movement, determinism, save, and export regression suite.
- Primary shipping target: Windows x86_64 via Steam. Linux/Steam Deck is an
  evaluation target, not a release blocker until representative hardware exists.
- Keep scene entry points thin. Simulation, presentation, camera, UI, and audio
  communicate through typed APIs and signals; resource data owns tuning.
- Prefer explicit composition and local ownership over global service access.
- Maintain a bootable main scene and a separate handcrafted movement test scene.

Planned source layout (created only as systems become concrete):

```text
autoload/       settings/save/input/log ownership
core/           small shared utilities with proven cross-system use
player/         controller, board presentation, camera rig, player tests
mountain/       chunk definitions, generation, streaming, validation, tests
biomes/         biome/surface resources and biome-owned content
hazards/        reusable hazard scenes and definitions
upgrades/       definitions, modifier evaluation, choice logic, tests
ui/             menus, HUD, settings, results, accessibility presentation
audio/          bus layout and runtime mixers
levels/         boot, handcrafted test course, run composition
tools/          in-game/debug-only instrumentation
tests/          headless integration and batch test runners
assets/         source-grouped game art/audio with provenance entries
```

Do not create empty architecture folders. Code and its focused tests may be
colocated when that makes ownership clearer.

## Runtime ownership

| Owner | Responsibility | Must not own |
| --- | --- | --- |
| `GameApp` main-scene coordinator | top-level boot/state transitions, screen/session host, pause policy, fatal recovery | player physics or procedural rules |
| `SettingsStore` autoload | versioned user preferences, apply/validate settings | run progression |
| `SaveStore` autoload | versioned profile and biome-checkpoint persistence, migrations | UI presentation |
| `RunContext` | immutable root seed, domain RNG creation, run facts | global entropy or scene loading |
| `RunSession` scene | active run phase, score, upgrades, biome transitions | settings persistence |
| `WindboardController` | fixed-tick movement state and collision response | camera/audio/VFX implementation |
| `BoardPresentation` | mesh posture, trails, particles, animation | simulation decisions |
| `FollowCameraRig` | look-ahead, FOV, damping, comfort settings | changing controller velocity |
| `MountainStream` | route plan, chunk lifecycle, ahead/behind windows | choosing presentation settings |

Signals publish meaningful state transitions (`landed`, `crashed`,
`surface_changed`, `speed_band_changed`) rather than per-frame copies of all
state. Critical state changes remain direct typed calls so ownership is visible.

## Movement architecture decision

Use `CharacterBody3D` with a custom ground/air integrator, shape casts for contact
prediction, and `move_and_slide()` for final collision resolution. This gives
direct control over feel, explicit crash rules, stable fixed-tick behavior, and
testable calculations. A free `RigidBody3D` is rejected because solver impulses
make exact steering and recovery difficult; a hybrid visual rigid body is deferred
unless animation tests prove it necessary.

Simulation runs in `_physics_process` at 60 Hz initially. Input is captured as an
intent snapshot; digital steering is rate-filtered while analog steering retains
proportional low input. A short support cast and separate velocity look-ahead cast
derive contact evidence and a filtered normal without grounding airborne riders.
Velocity is decomposed into tangent/downhill/lateral components, then affected by
gravity, tuck drag, carve force, surface profile, wind, and bounded assistance.
`move_and_slide()` remains the only collision resolver; supported model feedback
uses `get_real_velocity()` so slope displacement is not discarded, while landing
and wall classification consume stored pre-move velocity. Presentation interpolates
independently. Crash classification consumes relative impact speed, contact angle,
posture, hazard flags, and grace windows.

Required debug telemetry: speed, slope, contact state/normal, surface, lateral
slip, stability, crash cause, physics tick rate, and frame time. All tuning values
must expose units and safe ranges.

This approach must be replaced or revised before dependent production if the
Phase 2 course shows persistent high-speed tunneling, unstable slope contact, or
frame-rate dependence that shape casts and fixed-tick integration cannot solve.

## Mountain generation and determinism

Use controlled assembly of authored chunk scenes, not runtime heightmap noise.
Each `TerrainChunkDefinition` declares biome, entrance and exit sockets, bounds,
length, elevation loss, difficulty cost, route tags, safe corridor, hazards and
reward sockets, visibility cost, and compatibility tags. Geometry may contain
small seeded decoration variation that never changes collision viability.

Generation has two stages:

1. **Plan:** from the root seed, build a lightweight complete route graph for all
   three biomes, including branches/reconnections, budgets, rewards, and weather.
   Validate a continuous primary path and constraints before play.
2. **Stream:** instantiate a bounded window ahead of the rider, retain branch
   choices until reconnection, and recycle chunks safely behind checkpoints.

Randomness is never read from a shared global generator. `RunContext` derives
independent deterministic streams from `(root_seed, domain, stable_id)` for route,
hazards, rewards, weather, decoration, and upgrade choices. Adding a decoration
draw must not alter route topology. Generated plans serialize stable IDs and
quantized transforms for regression snapshots and failed-seed reproduction.

Validation rejects incompatible sockets, overlapping safe corridors, excessive
difficulty/visibility combinations, impossible jump envelopes, unavoidable
hazards, missing reconnects, and budget violations with actionable errors. The
initial soak target is 10,000 plans headless and 100 instantiated runs per release
candidate; thresholds are refined from measured generation cost.

## Data resources

Introduce each typed `Resource` only with its first real consumer and validation:

- `SurfaceProfile`: longitudinal drag, lateral grip, carve authority, stability,
  jump/landing multipliers, effects and audio surface key.
- `BiomeDefinition`: surface palette, generation rules, weather/visibility,
  hazard/reward pools, presentation references.
- `TerrainChunkDefinition`: generation metadata and packed scene.
- `HazardDefinition`: placement constraints, telegraph, severity, scene.
- `UpgradeDefinition`: localized description, modifier set, caps, conflicts,
  weight, unlock rule.
- `DifficultyProfile`: section budgets and escalation curve.

Runtime modifiers are evaluated in a deterministic fixed order: base controller,
surface, biome/weather, upgrades, temporary route effects, accessibility-safe
presentation only. Tests cover clamping and conflict behavior.

## State, settings, and saves

Top-level states: `BOOT → TITLE → RUN_LOADING → RUN_INTRO → DESCENT ↔ PAUSED →
TRANSITION → RESULTS`, with `DESCENT → CRASH → RESULTS`. Only `GameApp` performs
top-level transitions. Loading failures return to title with a diagnostic code.

Two separate versioned files use `ConfigFile` initially:

- `user://settings.cfg`: display, graphics, audio, input overrides, accessibility;
  invalid values clamp to defaults and can be reset by category.
- `user://profile.cfg`: schema version, unlock IDs, aggregate stats, last valid
  biome checkpoint (seed, plan signature, section, chosen upgrades). Writes use a
  temporary file followed by atomic replacement where supported, with one backup.

Never serialize nodes, script objects, engine RNG state, or executable variants.
Migrations are explicit functions from version N to N+1 and retain unknown future
data when safe. Corrupt profiles are quarantined, not overwritten silently.

## Input, pause, and device handling

Gameplay reads named actions through a small input-intent adapter. UI uses Godot
focus navigation and standard `ui_*` actions. Keyboard and common gamepads ship
with defaults. Runtime device changes update glyphs but never reset bindings.
Disconnecting the active controller pauses and shows a keyboard-operable notice.

Pause sets the tree paused; `SessionRoot` is explicitly pausable even though the
top-level coordinator, input service, pause UI, and debug overlay process always.
This keeps menu/controller-disconnect handling alive without advancing gameplay.
Focus loss optionally auto-pauses during descent. Seeds, input events, and
simulation errors are logged; raw personal paths and identifiers are not included
in user-facing diagnostics.

## Presentation and performance architecture

Camera, board posture, contact VFX, and player audio observe the controller through
state/signals and read-only snapshots; none writes velocity or movement state.
Precomputed deterministic Phase 2 wind/contact PCM loops prove the mixing seam
through `Effects` without per-frame sample generation and must be replaced or
intentionally retained at the later content gates. Session scenes expose explicit
shutdown for active audio and future streamed resources before deferred deletion.

Use one directional light, baked/probe lighting where helpful, selective local
lights, bounded volumetric fog, shared materials, shader variants kept explicit,
MultiMesh for repeated props, LOD/visibility ranges, opaque effects when possible,
and pooled transient VFX. SDFGI is off unless profiling shows a quality need that
fits all presets. Terrain streams; a full mountain is never resident or rendered.

Performance budgets and measurement conditions are canonical in
[quality-plan.md](quality-plan.md).

Large editable binary sources may use Git LFS once representative model/audio
sizes exist. The policy must be chosen before Phase 3 content import; Godot-generated
imports remain excluded and shipping-source ownership stays explicit either way.

## Failure handling and diagnostics

Expected invalid data returns typed validation results and blocks the affected
run with actionable context. Impossible internal states use `push_error`, record
the seed/build/state, and recover to title where possible. Debug builds expose a
toggleable overlay and route visualization; release builds keep structured logs
and seed reproduction without development cheats.
