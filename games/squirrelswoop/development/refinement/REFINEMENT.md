# Squirrel Swoop refinement

This work builds on the original game at `b68d4a1e1`, in a new worktree based on `d9b6219d1`. It preserves free movement across the meadow, stream, and woods, seeded retries, and the complete game flow. Everything remains procedural and independently runnable. No automated tests were created.

## Improvement cycles

1. **Fresh baseline.** Captured both actual flight and explicitly staged studies at reproducible coordinates, using the existing game. Independent reviewers identified the strongest problems: repeated trees and smooth ground, excessive sky, toy-like anatomy, forced six-metre altitude trim, and insufficient performance evidence.
2. **Structure and flight.** Added curved tree archetypes with matching wood collision, terrain-fitted roots, unequal formation spans, stream margins, a continuous character body and articulated limbs, and a flight model that retains altitude choices. Early flight review demonstrated 2,061 m of continuous play and all landscape crossings. It also found unacceptable canopy occlusion, dark materials, a floating distant backdrop, section stalls, and multiple rewards from one tree. These findings were kept as evidence, not treated as completion.
3. **Visibility and bounded work.** Corrected material color conversion, aimed the camera into the slope, fixed the distant forest placement, added larger rock shoulders and stream pockets, grouped close-pass rewards, and cleared soft foliage from the camera-to-character sightline. Split live generation into short intervals with cancellation on retries; replaced full nearby-grove collision scans with bounded spatial cells.
4. **Fresh diagnostics and correction.** Shadow comparisons identified ground ribbing as self-shadowing rather than soil texture. Adjusted shadow bias while retaining dappled light. A second inspection found reversed rock side faces, which made boulders look hollow; corrected winding and caps and aligned rocks and collision volumes to the local slope. Reduced repetitive coat relief and the cost of the full-screen brush filter. An actual-key retry then exposed a two-second neutral-launch collision on seed 752041; extended the initial clear area to 100 m so the camera settles before the first solid hazard.

## Comparable images

Studies deliberately reuse the same seed, world position, and height above terrain. Camera and terrain changes are part of the comparison. They demonstrate rendering at those locations, **not** a continuous descent to the displayed distance. The final review console labels these captures `STUDY` and reports `staged: true`.

| Scene | Before | After |
| --- | --- | --- |
| Summit, seed 482193 | [Baseline](baseline/summit-482193.png) | [Final](final/summit-482193.png) |
| Woods, seed 482193, 650 m, x=68, 6 m above terrain | [Baseline](baseline/woods-study-482193-d650.png) | [Final](final/woods-study-482193-d650.png) |
| Woods, seed 482193, 2,300 m, x=76, 5.5 m above terrain | [Baseline](baseline/woods-study-482193-d2300.png) | [Final](final/woods-study-482193-d2300.png) |
| Actual meadow flight, seed 752041, about 234 m | [Baseline](baseline/meadow-flight-752041.png) | [Final](final/meadow-flight-752041.png) |
| Stream, seed 752041, 820 m, x=0, 6 m above terrain | [Baseline](baseline/stream-study-752041-d820.png) | [Final](final/stream-study-752041-d820.png) |

An additional [woods study on seed 915772](final/woods-study-915772-d1150.png) checks another formation and lighting composition. The supplied [visual target](../visual-target.png) remains a development reference, never a displayed game asset.

## Flight and fairness

Neutral flight retains a useful clearance range rather than rapidly forcing every line to six metres. A short tuck trades height for speed; timely release preserves that energy. Pulling up still spends momentum, lift weakens at low speed, and the squirrel always descends. Optional ground recovery buys clearance at a modest speed cost. The [first independent flight review](cycle-1/flight-review/REVIEW.md) includes matched assistance-on/off measurements and a bounded full-pull experiment; those measurements are explicitly separated from continuous descents.

Terrain collision follows the exact rendered triangles. Curved wood and roots share their mesh segment definitions with collision. Rock placement respects neighboring routes and rotates both visual and collision volumes to the ground. Main woodland openings reserve the low flight band; solid limbs above it make higher lines a deliberate choice. Foliage, fur, and membrane tips remain soft. Reproducible formation descriptors and a long diagonal clearing preserve connected alternatives without route selectors or side walls.

## Final verification

Final runtime findings, frame-time windows, memory samples, capture conditions, and source fingerprints are recorded in [the independent final flight review](final/flight-review/REVIEW.md). The chronological console records distinguish actual key events, continuous play, and staged collision studies. Final scene captures and their source hashes are recorded separately in `final/studies.json` and `final/source-sha256.json`.

On the corrected final build, two neutral launches using actual Enter/R input events reproduced the same 941.291 m collision, position, speed, score, and three grouped close passes. A deliberately steered meadow descent reached 3,210.115 m over 150.3 seconds without staging. A short dive recovered; a subsequent sustained dive produced a ground impact at 30.076 m/s. Stream flight and free crossings were demonstrated separately. Deep woodland entries showed the risk of upper limbs on high lines; a separately marked staged start checked the lower passage through rock shoulders.

Actual keyboard navigation changed volume, assistance, reduced motion, and pitch inversion. Quitting and starting a fresh process restored all four settings and the 3,210 m / 3,510 point records. The original settings were restored afterward; launch and pause were checked again. These checks use the isolated development profile, leaving normal player records separate.

| Sustained final descent measurement | Observed result |
| --- | --- |
| Final 40-second window, no screenshot capture | p50 35.343 ms; p95 46.483 ms; maximum 57.282 ms |
| Earlier no-capture meadow window at 1,784 m | p50 45.814 ms; p95 66.448 ms; maximum 88.339 ms |
| Separate foreground woodland window to 250 m | p50 55.710 ms; p95 74.916 ms |
| Physics time / live generation interval at that window's end | 0.217 ms / 4.305 ms |
| Active sections / cached terrain vertices | 63 / 17,254 |
| Process RSS samples across the descent | 367.1, 369.0, 371.8, 370.8 MiB |

These samples demonstrate bounded residency over this descent, not an indefinite memory guarantee. Other game processes were active and their load changed during the session. Later occluded-window intervals were excluded because physics continued while rendering stopped; they cannot be used as evidence of higher rendered frame rates.

All frame intervals include the real rendered game. Screenshot writes and staged loading are excluded from sustained windows; screenshot capture can itself stall a frame. Godot static allocation is distinct from operating-system resident memory. Several other Godot games were running on the shared machine, so these results must not be presented as an isolated hardware benchmark or a universal frame-rate guarantee.

## Limits

The [independent final visual review](final/INDEPENDENT-VISUAL-REVIEW.md) confirms the resolved rendering defects and records the remaining differences. The scene is a coherent procedural stylization, not a reproduction of the reference's authored detail. Close foliage still exposes the generated needle-card technique; rocks and vegetation have less organic variety than the target, broad safe recovery areas remain deliberately open, and repeated bank stones can look arranged. The game has received repeated source and rendered-play reviews, but these do not establish subjective fun for a human player. Physical-controller feel, long-term human playtesting, and cross-platform performance have not been demonstrated. Synthesized audio ran during play; an independent listening assessment was not performed.
