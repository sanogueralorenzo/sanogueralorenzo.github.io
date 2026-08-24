# Production state

Last reviewed: 2026-08-23 · Current phase: **2 — Movement validation**

## Stage-gate roadmap

| Phase | Exit evidence | Status |
| --- | --- | --- |
| 0. Audit and preproduction | audit, coherent scope/decisions, risks, budgets, roadmap, backlog, definition of done | Passed 2026-08-23 |
| 1. Technical foundation | reliable boot/state flow, inputs/settings/save seams, diagnostics, tests, export validation, test level | Passed 2026-08-23 |
| 2. Movement validation | handcrafted course passes stability/feel gate and focused human playtest | In progress |
| 3. Frost vertical slice | representative polished section proves fun/readability/feasibility/quality | Not started |
| 4. Procedural mountain | deterministic valid streamed route batches, reproduced seeds, stable performance | Not started |
| 5. Biome/surface framework | definitions change simulation and presentation without controller duplication; Frost complete | Not started |
| 6. Core run/roguelite loop | launch-to-results 10–15 minute run with meaningful decisions and fast retry | Not started |
| 7. Content production | Frost, Dunes, Ashlands and transitions meet the content matrix | Not started |
| 8. Progression/UX/accessibility | new player can configure, learn, play, interpret, and progress unaided | Not started |
| 9. Art/audio/feedback polish | no unowned placeholders or visibly disconnected prototype-quality areas | Not started |
| 10. Balance/performance/QA | declared budgets and test matrix pass; no release blockers | Not started |
| 11. Release preparation | clean-install exports, credits/licenses/store materials/checklists/rollback ready | Not started |
| RC acceptance | every applicable criterion in `release.md` evidenced and limitation accepted | Not started |

Advancing a row requires a dated gate record with automated evidence, focused
manual evidence, known risks, and a harden/refactor/replace decision for prototype
work. “Implemented” is not exit evidence.

## Prioritized backlog

### P0 — Phase 0 gate

- [x] Inventory repository, engine/configuration, code, scenes, assets, plugins,
  inputs, tests, exports, and worktree state.
- [x] Decide initial equipment, controller, generation approach, biome arc, crash
  model, trick importance, progression boundary, art direction, target hardware,
  and Steam Deck expectation.
- [x] Record design, architecture, risks, budgets, test plan, asset/license state,
  placeholder policy, release definition, and staged roadmap.
- [x] Review independent audit results and resolve missing evidence (engine pin,
  CI gap, unverified icon provenance, and pre-content binary policy decision).
- [x] Record Phase 0 gate outcome and create the validated Phase 1 work breakdown.

### P1 — Phase 1 foundation (passed)

- [x] Add boot/main scenes and an explicit top-level state coordinator with a
  minimal title-to-test-level flow and recoverable loading errors.
- [x] Define gameplay/UI input actions and typed intent adapter; support keyboard
  and common gamepad defaults plus active-device observation.
- [x] Add versioned settings ownership and crash-resistant persistence with
  validation, backup recovery, future-schema protection, and smoke coverage.
- [x] Establish save/profile schema ownership and migration test fixtures without
  inventing progression content.
- [x] Add versioned root-seed parsing and domain-separated deterministic RNG with
  pinned derivation vectors and sequence tests.
- [x] Add a lightweight headless test runner, explicit suites, leak-free teardown,
  CI-friendly exit codes, and a shell guard for Godot's zero-exit parse failures.
- [x] Add structured logging, debug-only overlay, frame-time instrumentation, and
  development/release feature guards.
- [x] Build a reusable handcrafted test-level shell; no movement controller exists.
- [x] Add Windows/Linux debug/release export presets, install checksum-verified
  Godot 4.7.2 templates, and validate PE/ELF x86_64 packaging.
- [x] Reconcile the independent Phase 1 code review; no unresolved verified defect.
- [x] Inspect native Forward+ title/course/pause captures and exercise focused
  Start/Pause/Resume actions through the real UI input path.
- [x] Record the Phase 1 pass. Target-OS execution, physical controller coverage,
  and target GPU performance remain later required evidence; cross-export proves
  packaging only.

### P2 — Phase 2 movement validation (active, ordered)

- [x] Define measurable windboard motion states, units, tuning boundaries, contact
  probes, crash inputs, and initial Frost surface behavior before scene coupling.
- [x] Implement the smallest fixed-tick `CharacterBody3D` ground/air controller
  with explicit input intent and telemetry; keep camera/presentation independent.
- [x] Expand the handcrafted course to cover gentle/steep slopes, banks, sharp
  transitions, jumps, uneven contact, high speed, and a controlled crash case.
- [ ] Add follow-camera look-ahead/FOV/damping with comfort multipliers, board
  presentation, contact trail/particles, and placeholder surface/speed audio.
- [x] Add restart/crash flow, recoverable instability, landing classification,
  keyboard filtering, held recovery, and bounded gamepad vibration. Feedback and
  feel remain part of the unchecked presentation/playtest work.
- [ ] Add calculation/contact/state regression tests and run 30/60/120 fps plus
  low/high input and tunneling/jitter probes on the course.
- [ ] Request focused human playtest feedback using the questions in
  `quality-plan.md`; at least one non-implementer must test keyboard and gamepad.
- [ ] Record Phase 2 harden/refactor/replace decision and gate outcome. Do not begin
  procedural generation or declare the game complete at this gate.

Later work stays in the stage rows above until the preceding gate supplies enough
evidence for a concrete backlog. This prevents speculative content production.

## Definition of done

A task is done only when its intended player/production outcome works in the
integrated main project; affected tests and documentation are current; expected
errors fail clearly; debug-only behavior cannot leak into release; relevant
keyboard/controller and pause behavior is checked; performance impact is measured
when material; new assets have provenance/license entries; placeholders are
registered; and changes are reviewed, committed, and pushed to `main` after focused
validation. Manual-feel work also requires a dated playtest result.

A phase is done only when its stated objective—not merely its feature list—is
validated by its acceptance criteria and recorded in a gate outcome. The ongoing
goal is done only at the release-candidate gate.

## Decision log

| ID | Decision and reason | Revisit trigger |
| --- | --- | --- |
| D-001 | Fictional all-terrain **windboard**; preserves one deep controller and supports the supernatural pitch across all surfaces. | Movement playtest cannot communicate edge/carve behavior clearly. |
| D-002 | Custom `CharacterBody3D` controller; prioritizes authored feel, stable crash rules, and testable fixed-tick calculations. | Phase 2 shows unfixable contact/tunneling/frame dependence. |
| D-003 | Controlled authored chunk assembly, with procedural planning and cosmetic variation; viable routes remain designer-owned. | Content cost cannot meet variety target after vertical slice metrics. |
| D-004 | Every standard complete run uses Frost → Dunes → Ashlands; seed changes internal route/weather/content, while fixed macro pacing keeps scope and transitions coherent. | Repeated full-run tests show order fatigue that chunk variety cannot address. |
| D-005 | Mistakes first scrub speed/stability; clearly severe impacts or lethal hazards end a run; Gale Guard is a possible one-use upgrade. | Players cannot predict crash outcomes in blinded Phase 2 tests. |
| D-006 | Survival, route quality, near misses, airtime, and landings matter; no trick-combo system for release. | Core game is complete early and player tests strongly demand expression depth. |
| D-007 | Meta progression unlocks sidegrades/cosmetics only; no permanent performance stats. | First-run overwhelm requires a smaller staged starting pool. |
| D-008 | Graphic, faceted, windswept low-frequency art with a readable rider silhouette; geometry, light, and wind ribbons carry motion. | Vertical slice fails route readability or content throughput. |
| D-009 | Windows x86_64 is the committed launch target; Linux/Steam Deck is evaluated and documented but not promised without representative-device validation. | Product decision obtains hardware/test capacity and adds support explicitly. |
| D-010 | Resume only at biome transitions; no exact mid-slope save. This reduces corruption/desync complexity and reroll exploits. | Accessibility testing shows the checkpoint interval is exclusionary. |
| D-011 | Pin Godot 4.7.2 for initial production; engine upgrades require recorded regression evidence. | A release-blocking engine defect or necessary supported-platform fix. |

## Risk register

Probability/impact use Low, Medium, High. Owners are roles until staffing exists.

| ID | Risk | P/I | Mitigation and early evidence | Owner |
| --- | --- | --- | --- | --- |
| R-01 | Downhill contact feels unstable or arbitrary at speed | H/H | Phase 2 first; predictive probes, explicit crash telemetry, frame-rate matrix, replace decision before slice | Gameplay |
| R-02 | Authored chunks show seams/repetition or invalid routes | H/H | Socket contract, safe-corridor metadata, full-plan validator, seed soak, content metrics | Generation |
| R-03 | Three biomes exceed small-team content capacity | H/H | Finish Frost before expansion, shared framework, per-biome minimum matrix, fixed macro-order | Product/art |
| R-04 | Forward+ effects miss minimum GPU frame budget | M/H | low/medium/high presets from first representative slice, bounded streaming/fog/shadows, GPU captures | Tech art |
| R-05 | Keyboard steering is materially worse than analog | M/H | filtered digital intent, keyboard-only gate tests, separate sensitivity curve | Gameplay/UX |
| R-06 | Upgrades create dominant/exploit combinations | M/M | modifier order/caps/conflicts, property tests, combination matrix, sidegrades only | Systems |
| R-07 | Procedural determinism changes with refactors | M/H | domain RNG streams, stable IDs, plan snapshots, version/signature and failed-seed corpus | Generation/QA |
| R-08 | Camera motion causes discomfort | M/H | reduced shake/speed VFX, tunable look-ahead/FOV/distance, focused comfort playtests | Camera/UX |
| R-09 | Save changes lose progress | L/H | versioned primitives, sequential migrations, atomic write/backup/quarantine, fixtures | Platform |
| R-10 | Audio/art provenance is incomplete near release | M/H | register at import time, forbid untracked assets, periodic audit, replace list | Production |
| R-11 | No target Windows/Deck hardware is available for proof | M/H | define matrix now, use exported builds on available systems, treat untested platforms as unsupported | Production/QA |
| R-12 | One-person polish workload hides incomplete systems | H/H | explicit gates, acceptance evidence, blocker list, no phase advance on feature count | Product |
| R-13 | Large binary sources bloat the parent monorepo | M/M | choose Git LFS/source policy before Phase 3 imports; keep generated imports ignored | Production |

## Scope-control test

Every proposed feature must identify the strengthened pillar, implementation and
content cost, test/balance/maintenance cost, an existing-system alternative, and
schedule/performance risk. If it cannot replace or outrank current backlog work,
record it below rather than starting it.

Postponed: Stormpeak; tricks; ghosts; leaderboards; daily seeds; achievements;
Steam Cloud; extensive cosmetics; replay camera; photo mode; online services.
