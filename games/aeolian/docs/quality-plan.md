# Performance budgets and test plan

Last reviewed: 2026-08-24 · Owner: engineering/QA · Status: initial measurable targets

## Target hardware matrix

Targets are production decisions, not measured results. Hardware availability is
tracked as a risk and measurements must name machine, OS, build, resolution,
preset, route/seed, and sample duration.

| Tier | Target | Expected result |
| --- | --- | --- |
| Minimum Windows | Windows 10 64-bit; 4-core Intel i5-6600 / Ryzen 3 1200 class; 8 GB RAM; GTX 1050 Ti / RX 570 class with DirectX 12 support; SSD | 1920×1080 Low, stable 60 fps target with rare 1% lows no worse than 45 fps |
| Recommended Windows | Windows 11 64-bit; 6-core i5-10400 / Ryzen 5 3600 class; 16 GB; GTX 1660 / RX 5600 XT class; SSD | 1920×1080 High, stable 60 fps; 1440p Medium 60 fps |
| Development smoke | macOS development machine, editor and local exports where supported | correctness and profiling only; not a promised launch target |
| Steam Deck evaluation | current SteamOS / 16 GB APU handheld, native Linux or Proton | 1280×800 Medium-derived preset at stable 40 fps only if later retained in scope |

The current Windows renderer is D3D12, matching project configuration. Linux and
Steam Deck builds use Vulkan. D3D12 retention versus Vulkan parity is a Phase 3
profiling decision and must be tested on the declared minimum GPU before support is
claimed.

Minimum GPU/CPU names are provisional until representative vertical-slice builds
are profiled; raising them requires a recorded product decision.

Distribution guardrail: target no more than 4 GB installed and 2 GB compressed
download for the release scope. This is a content-production constraint, not yet
a measured build size.

## Runtime budgets

Measured in release exports after a 60-second warmup; editor results are diagnostic.

| Budget | Minimum / 1080p Low | Recommended / 1080p High |
| --- | --- | --- |
| Frame time | p95 ≤16.67 ms; p99 ≤22.2 ms | p95 ≤16.67 ms; p99 ≤18.2 ms |
| Game-thread physics | p95 ≤3.0 ms | p95 ≤2.0 ms |
| Mountain generation | ≤4 ms work in any rendered frame; plan ≤250 ms async/loading | same |
| Startup to interactive title | ≤8 s cold SSD, ≤4 s warm | ≤5 s cold, ≤3 s warm |
| Crash/retry to player control | ≤3 s | ≤2 s |
| Biome transition | ≤4 s with no unresponsive frame >100 ms | ≤3 s |
| Resident memory | ≤2.5 GB peak | ≤3.5 GB peak |
| VRAM estimate | ≤2.0 GB | ≤4.0 GB |
| Draw calls | ≤1,200 visible frame | ≤1,800 visible frame |
| Visible rendered objects | ≤1,500 | ≤2,500 |
| Active particles | ≤20,000 GPU-equivalent; ≤500 CPU | ≤50,000 GPU-equivalent; ≤1,000 CPU |
| Shadow distance | ≤120 m, one cascade-light policy | ≤250 m, tuned cascades |
| Stream window | memory bounded; target ≤7 trunk chunks plus unresolved branches | target ≤9 plus unresolved branches |

Budgets are guardrails and may be revised from evidence, but never silently. Avoid
averages that conceal traversal spikes. Capture p50/p95/p99 and worst frame.

## Automated test layers

1. **Pure calculation tests:** seed parsing/domain RNG, modifier ordering/caps,
   score, difficulty budgets, save migration, input curve calculations.
2. **Scene integration tests:** state transitions, pause/focus, active-device
   changes, player landing/crash signals, chunk sockets and lifecycle, UI focus.
3. **Generation tests:** same seed/stable signature, connectivity/reachability,
   compatible transforms, difficulty bounds, unavoidable-hazard checks, invalid
   definitions, and large seed batches with failure corpus retention.
4. **Export smoke tests:** clean user directory, boot/title/run/results/retry,
   settings persistence, keyboard/controller navigation, logging, quit behavior.
5. **Soak/regression:** repeated complete runs, restart loops, long sessions,
   controller reconnect, alt-tab/focus loss, biome transitions, upgrade matrices,
   30/60/120 fps caps, and deliberately stressed frame pacing.

Tests must use CI-friendly exit codes, log seed/build on failure, and avoid tests
that only assert engine behavior. Generated snapshots compare relevant stable data,
not incidental node order or floating-point text.

## Manual playtest gates

Automation cannot approve feel, readability, comfort, difficulty, atmosphere, or
pacing. Each meaningful gate records build/commit, hardware/input, tester context,
questions, observations, severity, and decision.

### Phase 2 movement questions

- Without explanation, can the tester predict how to gain and shed speed?
- Do gentle/steep slopes, banks, transitions, jumps, and rough terrain preserve a
  consistent mental model at low and high input values?
- Can every crash be explained from the preceding action and feedback?
- Are landing correction and recovery helpful without feeling automated?
- Does the camera reveal the next decision without causing discomfort?
- Is immediate retry fast enough to invite another attempt?

Approval requires no unexplained terminal crash, visible sustained contact jitter,
repeatable tunneling/accidental launch, or material behavior change across tested
frame rates. At least one tester other than the implementer must complete the
course on keyboard and gamepad before the gate closes.

Current automated checkpoint (2026-08-24): pure movement/input/course calculations
and the integrated scene matrix pass through the normal boot/session path. The
scene matrix includes separate continuous analog and keyboard-filtered 486 m
spawn-to-finish traversals, a true terrain gap, smooth crest/compression, banks,
bounded roughness, recoverable terrain-normal stress, pause/resume invariants,
twenty in-place restarts, successful and missed endpoint lanes, 42 m/s terrain
contact, and 30/42 m/s wall impacts. The continuous traversals prove route and
input-path viability with conservative steering policies, not human feel or parity.
Native Forward+ layout capture covers title, course, speed, recovery guidance,
pause, finish-gate approach, deterministic completion, and crash/restart guidance
on the development Mac. The capture waits on explicit UI state, a brief real-time
settle, and five completed renderer draws so archived PNGs cannot precede the tested
layout transition. `./scripts/visual-smoke.sh` also rejects engine errors, teardown
leaks, and missing frames. Native Metal Forward+ replays at measured 30/60/121
rendered fps produced exact matching endpoint position, speed,
state, crash result, and event signatures for crest, bank, terrain-jump, and fatal
wall scenarios at fixed 60 Hz physics. The cadence harness uses Dummy audio to
isolate rendering/physics. This closes the development-machine render-cadence row,
but not physical-controller, target-PC, comfort, or human-feel rows. After the
current HUD and endpoint changes, an unlocked-display 120 FPS rerun is pending: the
locked macOS session held a 120 request at 60 rendered FPS, and the verifier
correctly refused to accept that row rather than weakening its precondition.

### Later focused questions

- Slice: route choices readable at speed; reward/hazard value understood; visual
  and audio direction cohesive; quality appears producible.
- Generation: generated routes feel intentional; repeated patterns are acceptable;
  failed seeds reproduce; no choice is fake or unknowable.
- Full run: pacing fits 10–15 minutes; each biome changes decisions; upgrades alter
  style without producing mandatory picks; failure/result/retry is clear.
- UX/accessibility: a new player configures and plays without developer help;
  comfort options materially reduce triggers and do not change competitive stakes.
- RC: complete exported-build matrix, clean install, long soak, regression pass,
  and accepted limitation review.

## Defect policy

P0 blocks testing or risks data/system integrity. P1 blocks completion, creates an
unavoidable invalid route/crash, breaks required input/accessibility/save/export,
or misses minimum performance materially. P2 harms polish/readability but has a
workaround. P3 is minor. RC permits no open P0/P1; every P2 must have an explicit
ship decision, owner, and player impact. Repeated symptoms require root-cause work.
