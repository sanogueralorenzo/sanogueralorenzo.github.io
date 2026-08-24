# Phase 2 movement specification and gate record

Last updated: 2026-08-24 · Status: **in progress** · Owner: gameplay

## Objective and boundary

Validate that descending a handcrafted course on the windboard is stable,
predictable, responsive, comfortable, and enjoyable before procedural terrain or
production content depends on it. Phase 2 may use intentional primitive visuals
and audio, but the integrated main project must remain runnable. Passing this gate
does not make a vertical slice or completed game.

## Coordinate system, units, and states

- Godot units are metres; velocity and acceleration are m/s and m/s²; angles shown
  to tuners are degrees; simulation remains at the pinned 60 physics ticks/second.
- Global up is `+Y`; the initial fall line is `-Z`. The collision body remains
  upright for stable capsule contact while its presentation aligns to the filtered
  surface normal and travel heading.
- Motion states are `GROUNDED`, `COYOTE`, `AIRBORNE`, `CRASHED`, and `FINISHED`.
  Landing emits `CLEAN`, `RECOVERABLE`, or `CRASH`; speed alone is never a crash
  condition. `FINISHED` freezes motion but continues sampling immediate restart.
- `CharacterBody3D` owns collision queries, floor/wall classification, motion, and
  respawn. `WindboardMotionModel` owns heading, velocity, grip/drag, stability,
  jumping, air control, and impact classification. Camera, mesh/VFX, audio, and UI
  observe controller state and never write simulation velocity.

## Initial measurable tuning contract

The initial hardpack target is deliberately bounded, not claimed as final feel:

| Property | Initial value / rule |
| --- | --- |
| Gravity | 9.8 m/s² × 1.1, projected along the contact plane while grounded |
| Ground / air cap | 42 / 48 m/s (151 / 173 km/h); caps are safety rails, not acceleration sources |
| Steering | 76°/s near rest → 34°/s by 32 m/s; tuck retains 62% authority |
| Input response | Keyboard steer attacks at 7/s and releases/reverses at 10/s; analog uses a 1.15 signed-power curve and configured sensitivity |
| Grip | lateral velocity moves toward zero at 15 m/s²; braking raises grip ×1.4 |
| Drag | 0.22 m/s² base; tuck ×0.28; carve up to +3.2; brake up to +11 m/s² |
| Jump | 7 m/s along surface normal; 0.12 s coyote time; 0.14 s recontact grace |
| Contact | 58° maximum floor; 0.28 m snap; 0.45 m current-support cast; separate velocity look-ahead cast; 0.02 m safe margin |
| Clean landing | normal impact ≤7.5 m/s and velocity/heading alignment ≥0.65 |
| Terminal landing | normal impact ≥16 m/s, or alignment ≤0.2 with impact ≥6 m/s |
| Wall crash | incoming normal speed ≥14 m/s; glancing/slow contact scrubs speed instead |
| Stability | 0–1; drains above 0.28 lateral-slip ratio or when accepted terrain normals change faster than 300°/s, recovers 0.34/s (×1.75 while recover is held), and must remain empty for 0.35 s before a posture crash |

All values live in `WindboardTuning` with units/ranges. Frost hardpack multipliers
live in one `SurfaceProfile`; additional surfaces are not introduced until a
specific course test requires them.

## Contact and movement rules

1. A short downward `ShapeCast3D` supplies close current-support evidence; a
   separate velocity-directed cast observes upcoming transitions without declaring
   an airborne rider grounded. `move_and_slide()` remains authoritative for actual
   collision response, landing, and floor/wall slide data.
2. Ground normals are filtered exponentially but never used to manufacture floor
   contact. The heading and velocity are projected onto the accepted contact plane.
3. Gravity projected along the plane creates acceleration. Floor snap is the sole
   positional adhesion mechanism; no persistent inward velocity or manual position
   correction is combined with it. Steering rotates the desired heading; bounded
   lateral grip redirects existing momentum. No arbitrary forward motor accelerates
   the board.
4. Rolling, carve, and brake drag remove speed without reversing velocity. Tucking
   reduces base drag and steering authority, creating an explicit speed/control
   tradeoff.
5. Jumping removes inward normal velocity, adds the surface-scaled jump impulse,
   disables snap during recontact grace, then enters air integration. Air steering
   redirects horizontal velocity at a bounded acceleration and cannot add energy.
   The shared jump/recover action jumps from composed ground, braces instead when
   grounded stability is below 0.75, and aligns heading toward travel while held
   in air.
6. On landing, pre-collision velocity is classified against the new floor normal
   and heading. Recoverable landings reduce stability and momentum with feedback;
   terminal landings enter `CRASHED`. Sustained severe slip can also exhaust
   stability. Rapid terrain-normal changes above the data-driven threshold apply
   bounded, surface-scaled instability with wobble, audio, camera, and haptic
   feedback. Stability damage remains continuous while observer transients are
   rate-limited to one every 0.20 seconds; ordinary authored roughness remains
   below the activation threshold.
7. Wall crashes use incoming normal speed. A collision normal within the floor
   angle is never reclassified as a wall merely because the board is fast.
8. Restart restores the authored spawn transform, heading, stability, camera, and
   transient effects in place; target input-to-control time is under 0.5 seconds in
   this local course and under 3 seconds for the eventual run flow.
9. Crossing the authored teal gate inside its bounded lane enters `FINISHED` once,
   records elapsed fixed-tick time, stops movement, and exposes restart. The course
   resolves the interpolated crossing point once, so entering the lane after missing
   the gate cannot become a completion. Crossing beyond the terrain end after a miss
   produces `missed_finish`; the rider never falls indefinitely past the endpoint.

## Required telemetry

Debug overlay fields: motion state, scalar speed, tangent/lateral speed, slip ratio,
stability, grounded/probe contact, raw/filtered normal, slope degrees, heading,
surface ID, coyote/recontact timers, last landing impact/alignment/severity, last
wall impact, last terrain-normal stress, crash cause, last completion data, physics
FPS, rendered FPS, and respawn count. A fixed-size event history records only meaningful
state/contact/landing/stress/crash transitions, not per-frame spam.

## Automated acceptance evidence

- Pure model tests: flat drag, downhill acceleration, tuck/brake tradeoffs,
  steering/grip, no energy-gaining air control, jump impulse, finite input guards,
  landing bands, wall impact, slip/terrain-normal stability drain and recovery,
  speed caps, and 30/60/120 Hz convergence over equal simulated time.
- Scene tests: no sustained grounded jitter, snap survives small seams, jumping
  leaves/reacquires floor, landing signals once, slow wall glances do not crash,
  terminal impacts do, separate continuous analog and keyboard-filtered controller
  traversals reach the finish, finish/missed-finish resolve once, respawn is clean,
  and state does not depend on rendered FPS.
- Course/runtime matrix and human questions remain canonical in `quality-plan.md`.

## Implementation checkpoint — 2026-08-24

- Production seams now exist as `WindboardMotionModel`, `WindboardController`,
  `WindboardInputFilter`, `WindboardTuning`, and the first concrete Frost hardpack
  `SurfaceProfile`. Simulation, collision, presentation, camera, and overlay remain
  separately owned.
- The integrated course is a deterministic 486 m diagnostic descent with a flat
  calibration deck, 8° and 24° slopes, Hermite crest/compression, ±18° bank ribbon,
  bounded roughness, a true 8 m jump gap, landing slope, 22° high-speed runway,
  recovery mound, safe lane, and 1 m-thick wall target. The two sides of the jump
  are each one welded concave collision mesh; render and collision share vertices.
- Pure tests cover gravity/drag/grip/steer, tuck/brake, air energy, jump, landing
  bands, wall closure, stability/recovery, caps, finite guards, equal-time
  30/60/120 Hz calculations, input response, and analytic course continuity.
- Real-scene tests boot through `GameApp` and the actual autoload/session path.
  They cover the start deck, gentle acceleration, analog response, tuck/brake,
  explicit jump/landing, crest, compression, banks, rough contact, authored gap,
  a 42 m/s runway, pause/resume without an impulse, a nonterminal recovery mound,
  separate continuous 486 m analog and keyboard-filtered spawn-to-finish traversals
  through the authored terrain gap, successful and missed finish lanes, 30 and
  42 m/s wall impacts, and twenty input-driven resets without session or player
  duplication. The traversals use conservative position-and-momentum feedback
  policies only to prove route and input-path viability; they do not stand in for
  player feel, readability, input parity, or difficulty approval.
- The course exposed and now guards a critical integration defect: feeding
  `CharacterBody3D.velocity` back after slope resolution discarded the downhill
  component every tick. Supported motion now consumes `get_real_velocity()`, while
  collision classification still uses stored pre-move velocity.
- Independent review also exposed two resolved edge cases: forceful impacts inside
  coyote grace now pass through landing classification, and exactly backward travel
  now drains stability instead of appearing perfectly composed. Controller-level
  regressions cover contextual bracing and the hard-coyote-recontact crash path.
- An expanded pause/recovery/restart matrix exposed two resolved integration
  defects: the always-processing application root allowed gameplay to continue
  under the pause menu, and the authored recovery mound launched the rider without
  producing stability feedback. `SessionRoot` is now explicitly pausable, while
  bounded terrain-normal stress makes the mound recoverable and leaves ordinary
  roughness below its activation threshold.
- A native Metal Forward+ smoke capture verifies current spawn/camera/course
  visibility. It is graphical integration evidence, not movement-feel approval.
- Camera look-ahead now expands with speed, FOV eases from 72° to a bounded 82°,
  impact shake respects the existing 0–1 comfort setting, and restart resets camera
  transients. Board lean, instability wobble, crash pose, hardpack trail, and snow
  spray remain presentation observers and cannot mutate simulation.
- Placeholder generated wind, hardpack-contact, and impact audio route through the
  `Effects` bus; `Music` and `Effects` settings now apply to concrete buses. These
  deterministic PCM loops intentionally prove runtime ownership/mixing only and
  remain on the Phase 3/9 replacement register. They are precomputed at session
  load rather than mixed sample-by-sample in gameplay, and session shutdown stops
  and releases their streams explicitly.
- Low stability shows a concise keyboard/gamepad recovery cue. A terminal crash
  names the failure class and presents the immediate restart binding. Native
  visual-smoke capture guards both states plus deterministic course completion
  alongside title, course, speed, and pause.
- The endpoint flow exposed and now guards a coyote-contact defect: a hard surface
  recontact first seen by the support probe could previously bypass landing severity
  as ordinary contact recovery. Probe-supported coyote recontacts now classify
  both impact and travel alignment before grounded integration, matching
  physical-floor recontacts; a low-closure sideways impact is a regression case.
- Finish resolution uses the rider segment that crosses the gate plane and latches
  that result for the run. Re-entering the lane downstream cannot convert a miss,
  completion timing is derived from fixed physics ticks, and terminal restarts
  publish explicit `FINISHED`/`CRASHED` to `GROUNDED` state transitions.
- A native Metal Forward+ cadence harness replayed crest, bank, terrain-jump, and
  42 m/s wall scenarios at measured 30, 60, and 121 rendered fps while physics
  stayed at 60 Hz. Endpoint position, speed, motion/crash state, and ordered event
  signatures matched exactly across all three runs; the verifier also enforces
  5 cm / 0.1 m/s numeric ceilings. The harness isolates renderer cadence with
  Godot's Dummy audio driver, suppresses real desktop focus/input pause events only
  during the diagnostic process, and retains JSON evidence under ignored `reports/`.
- CoreAudio on the development Mac can emit Godot ObjectDB playback warnings when
  a diagnostic process quits immediately after active audio. Normal session
  teardown is explicit and the cadence harness is clean, but exported-build quit
  behavior remains a later platform QA row rather than being silently accepted.

## Gate outcome

Still in progress. Automated calculation, contact, low/high-input, tunneling,
jitter, restart, and native render-cadence evidence now passes. Camera, contact
VFX/trail, speed/surface audio, recovery feedback, and comfort still require human
tuning; physical-controller evidence and focused non-implementer keyboard/gamepad
playtesting remain. The post-HUD-and-endpoint 120 FPS native rerun also requires a
development display session that actually presents above 60 Hz. On 2026-08-24 the
focus/input-isolated 120 request completed every scenario but measured exactly
60 FPS, so the strict verifier rejected it; 30/60 outcomes still match and no
acceptance ceiling was weakened. At exit, record whether the movement code is hardened,
refactored, or replaced before Phase 3 depends on it.
