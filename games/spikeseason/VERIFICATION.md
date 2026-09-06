> Historical 3D iteration record. Current renderer changes and verification are in [FORWARD_PLUS.md](FORWARD_PLUS.md). Earlier visual approvals do not cover the later migration.

# Spike Season — 3D runtime verification

This record distinguishes live behavior, assisted inspection, source review, and aesthetic judgment. No automated tests, bots, score overrides, unlock overrides, or external assets were used. The optional localhost console sends individual manual inputs through normal game functions. The [earlier 2D verification](VERIFICATION_2D.md) is historical; it is not approval of this rebuild.

## Before and after

The starting implementation drew scenery, projected court geometry, and athletes on a 2D canvas. The rebuild renders actual Node3D scenery, articulated meshes, a perspective camera, dimensional court/net, lighting and shadows. The simulation remains the match director; rendering never awards a point.

| Evidence | Scope |
| --- | --- |
| [Before: normal 2D rally](evidence/3d/before-normal-rally.png) | Recorded before replacing the presentation |
| [After: coastal rally](evidence/3d/coastal-restored-faces.png) | Normal authored camera, six athletes, compact HUD |
| [Coastal gameplay recording](evidence/3d/representative-coast.mp4) | 90 seconds, 1280×720, synthesized audio; see capture method below |
| [Harbor / Gardens recording](evidence/3d/harbor-gardens-gameplay.mp4) | 60 seconds with audio, manual shots and a pause/leave/season transition |
| [Recording rally ledger](evidence/3d/representative-coast-ledger.json) | Actual 5–1 warm-up, 68.8 game seconds, longest rally six contacts |
| [Harbor high tide](evidence/3d/maps/season-05-high-tide.png) | New quay, boats, lighthouse and maritime buildings |
| [Garden standalone play](evidence/3d/maps/standalone-gardens-rally.png) | Fresh project-only launch, orchard, pergolas, fountain and planted terraces |
| [Map review](evidence/3d/maps-visual-review.md) | Golden hour, harbor and garden seasonal variations; corrected support/planting rechecks |

The movie is Godot Movie Maker output at fixed 60 FPS and game speed 1x, with manual lane/shot choices and no timed contact or movement inputs. It includes the warm-up result. Encoding slowed wall-clock playback (90 seconds captured in 111 seconds); it is a visual/audio record, **not** a real-time performance benchmark or a human reaction-time measurement. H.264/AAC conversion changes only encoding. No gameplay outcome was edited. The separate 60-second venue recording used the same fixed-frame method (84 seconds wall time), beginning in Harbor lights with left tips, then manually leaving that attempt and selecting Summer thunder with deep-left power. It documents ordinary camera motion, contacts, ambience and the map transition, not completion of those two championships.

The art target informed court perspective, six-player composition, warm terracotta, matte seaside architecture, foliage, palette, expressive original athletes, and restrained cream/teal UI. It is not a backdrop. Independent reviewers approved the specific construction, pose, and readability repairs; they did not claim equivalence to the reference's painterly craft. Cloth/skin surfaces and environmental shapes remain simpler than that illustration.

## Independent reviews and corrected findings

- [Visual fidelity and coastal construction](evidence/3d/visual-review.md): normal camera composition, athlete scale, facial expressions, eyes, jersey/shoulder intersections, scenery depth and HUD. Failed iteration captures remain identified in the report. Final targeted restarts confirmed closed shoulder junctions, restored faces, and no tan skin wedges through the jersey.
- [Animation and contact](evidence/3d/animation-review.md): planted stance feet, forearm receive platform, gathered/extended set, asymmetric spike anticipation and follow-through, real block palm contact, continuous airborne recovery after a block rebound, and missed dives stopping visibly short.
- [Beginner accessibility and native flows](evidence/3d/beginner-review.md): normal-speed no-timing play, championship/drafts, actual process restart, native keyboard/menu/settings operation, loss/reset, and focused pause/timing fixes.
- [Advanced challenge and progression](evidence/3d/advanced-review.md): normal-speed late play, timing upgrade consequences, all-nine forward progression, saved crowns, replay, and the fixed-cycle weakness that prompted further defense changes.
- [Other venues](evidence/3d/maps-visual-review.md): six-player and ball visibility in warm/cool lighting, distinct geography, supported lighthouse and varied garden walls.

The presentation repairs changed no dig scoring thresholds. Rendering uses the same reach boundary and shows failed attempts short of the ball. Block detection was corrected to use the actual finite shoulder/arm envelope in the compact court for both teams. Legal platform and palm contacts, and a missed dig with the resulting score, are preserved in [contact-repairs](evidence/3d/contact-repairs/).

## Demonstrated play and progression

Fresh 3D beginner play, without Space or manual movement, won a warm-up **5–2 in 102.8 seconds**. Choosing a new lane/tip changed the outcome of a 27-contact exchange. A full first-season championship then won **5–1 / 5–1 / 5–1 in 233 game seconds**, drafting Soft touch and Perfect connection. The final required switching away from a covered right tip. Crown 1 and season 2 were genuinely earned; the save survived a subsequent actual restart.

The later native review selected season 2 through keyboard focus, confirmed season 3 remained disabled, saved sound off/reduced motion through real buttons, and restarted to verify both persisted. A replay earned Court vision, then an unchanged middle-roll semifinal lost **0–5** under explicitly assisted 4x playback. Its temporary upgrade cleared; earned unlocks survived. Native replay reset score, round, ledger, and upgrades.

An early 3D season-nine quarterfinal won **9–7 in 309 seconds** at ordinary unpaused 1x. Lane and shot changes mattered, but a 57-contact unchanged exchange exposed pacing risk. An upgraded excellent input at **0.17 seconds** remaining succeeded outside the base 0.13-second window, then the same poor power route was blocked. This was slowed/manual timing inspection, not evidence of normal-speed timing skill.

The forward review began with a byte-for-byte copy of the freshly earned 3D beginner save (only crown 1 / season 2 unlocked), then genuinely earned seasons 2–9. It used 4x playback and manual pauses where disclosed; later season-nine semifinal/final were unpaused 1x. No unlock fields were edited. Full ledgers and exact methods are in the advanced report.

| Season | Fresh forward championship scores | Evidence |
| --- | --- | --- |
| 1 | 5–1 / 5–1 / 5–1 | [Beginner review](evidence/3d/beginner-review.md) |
| 2 | 5–0 / 5–0 / 5–1 | [Ledger](evidence/3d/season-02-forward-champion.json) |
| 3 | 5–0 / 5–0 / 5–0 | [Ledger](evidence/3d/season-03-forward-champion.json) |
| 4 | 5–3 / 5–0 / 5–0 | [Ledger](evidence/3d/season-04-forward-champion.json) |
| 5 | 5–2 / 5–0 / 5–0 | [Ledger](evidence/3d/season-05-forward-champion.json) |
| 6 | 5–0 / 5–1 / 5–0 | [Ledger](evidence/3d/season-06-forward-champion.json) |
| 7 | 5–0 / 5–0 / 5–0 | [Ledger](evidence/3d/season-07-forward-champion.json) |
| 8 | 5–1 / 5–0 / 5–0 | [Ledger](evidence/3d/season-08-forward-champion.json) |
| 9 | 5–0 / 5–1 / 5–0 | [Ledger](evidence/3d/season-09-forward-champion.json) |

These ledgers establish progression, not final late-season balance: the reviewer found that two short tips followed by three deep-left powers dominated seasons 7–9, even winning a normal-speed final 5–0 without useful upgrades or hitter changes. Approval was withheld and the final defense was revised. The historical failed-build ledgers are deliberately retained.

Late defenders now preserve one deep wing when the other comes forward, choosing coverage from previous short/deep landings. Seasons 8–9 can shade the net toward a repeatedly used hitter route. The commitment occurs during the set, remains visible through contact, and uses unchanged finite movement/reach; current uncommitted player input is not consulted. Matching the player's defensive lane choice gives the same route coverage. The revised replays won seasons 7, 8, and 9 at **5–0 / 5–0 / 5–0**, **5–2 / 5–0 / 5–0**, and **5–1 / 5–3 / 5–0**, respectively. Their [S7](evidence/3d/counter-07-adaptive-champion.json), [S8](evidence/3d/counter-08-adaptive-champion.json), and [S9](evidence/3d/counter-09-adaptive-champion.json) ledgers preserve the outcomes. Season 7's quarterfinal ran wholly at unpaused 1x (70.7 seconds); season 8's quarterfinal likewise ran at 1x (84.4 seconds), using lane, shot and hitter changes after stale attempts were returned or blocked. Other revised matches used disclosed 4x playback/manual pauses.

A normal-speed sample retaining the old left-power policy lost **3–5 in 89.7 seconds**, including four actual block losses; tool/input latency means it is a policy-family comparison rather than an exact controlled reproduction of two tips/three powers. Repeated right tips separately lost 0–5 under assisted playback. A long unchanged left-tip exchange was broken on the next attack by changing hitter and shot. These outcomes support useful counterplay and the specific exploit correction; they do not prove optimal balance. Final physical-contact/coaching results are in the advanced report.

A final upgrade audit also restored Court vision's target display, which had been omitted when the 2D drawing was replaced. Its cream-edged orange world marker and explicit shot/lane cue now appear during the rival's set/attack. The primary check [earned the upgrade](evidence/3d/scouting-earned-offer.json) through a 5–1 quarterfinal at assisted 4x, then inspected the cue at 0.05x. [Target screenshot](evidence/3d/scouting-restored-target.png) and [state](evidence/3d/scouting-restored-target.json) confirm the actual rival lane and earned `read` upgrade; the independent beginner report records the final contrast/visibility recheck. The underlying conditional 0.13-second reaction improvement was preserved.

## Runtime and standalone delivery

Godot 4.7.2 / Forward+ / Metal on Apple M3 Max; logical viewport 1440×810, window 1280×720, MSAA and matte surface/foliage shaders. Match simulation advances at fixed 120 Hz; contact/movement outcomes do not depend on renderer cadence. Review speed and camera inspection are included in telemetry so assisted evidence is distinguishable.

A copy at `/tmp/spike-season-3d-standalone` contained only this project, excluding `.godot`, evidence, and all other games. Its own `launch.sh` launched successfully, rebuilt assets locally, and played Garden/Harbor/Coast seasons without script errors. [Standalone runtime state](evidence/3d/standalone-runtime.json) and the screenshot above preserve this check. The folder was a verification copy, not a runtime dependency.

Concurrent native sessions ranged from roughly 30–61 FPS; several other Godot games/reviews were active, so those values cannot isolate this game's GPU cost. Shutdown may report a small number of ObjectDB resources still active; runtime logs contained no script errors. Final foreground native observations sampled the last 600 wall-clock frames before screenshot readback, with no recording and game speed 1x. Each sample covers about ten seconds of active match play (including normal point/serve transitions):

| Venue | Mean frame | 95th / 99th percentile | Worst frame | Evidence |
| --- | --- | --- | --- | --- |
| Coast | 16.67 ms | 17.65 / 18.78 ms | 19.43 ms | [State](evidence/3d/performance-coast-active.json) |
| Harbor | 16.67 ms | 17.47 / 18.48 ms | 19.21 ms | [State](evidence/3d/performance-harbor-active.json) |
| Gardens | 16.67 ms | 17.48 / 18.53 ms | 20.68 ms | [State](evidence/3d/performance-gardens-active.json) |

The frame cap is 60 FPS. An older Spike comparison, another game's review, and the advanced review process were still open; they were not forcibly closed. These are measured foreground-session observations, not an isolated GPU benchmark, long-duration stress result, or guaranteed minimum. Earlier background/concurrent sessions recorded about 30 FPS. Venue construction and initial shader compilation are excluded from the ten-second samples and can cause a pause when first opening a different map.

## Limits of the evidence

Passing specific runtime checks does not certify subjective fun, universal absence of long rallies, accessibility for every disability, or performance on untested hardware. Some unchanged or poorly placed attacks can sustain long rallies; the coaching suggests lane/hitter changes. Keyboard and mouse menus were exercised; gamepad and touch gameplay are not implemented. The source runs independently with Godot; native export binaries are not bundled. Synthesized audio is present in the recording; its perceived quality remains subjective. Saved unlocks and crowns persist; in-progress matches are intentionally not resumable after exiting.
