# Independent visual review

Reviewed September 6, 2026. This review compares rendered images and relevant geometry/material source. It does not certify movement feel, collision fairness, sustained performance, or subjective enjoyment.

## Images compared

Reference: `development/visual-target.png`.

Baseline images in `development/refinement/baseline/`:

- `woods-flight-482193.png`
- `woods-study-482193-d650.png`
- `woods-study-482193-d2300.png`
- `meadow-flight-752041.png`
- `stream-study-752041-d820.png`
- `summit-482193.png`

Intermediate `cycle-1/` and `cycle-2/` captures were reviewed to identify and recheck character shading, repetitive fur relief, floating backdrop geometry, ground ribbing, and rock construction defects. The cycle-2 `woods-entry-482193.png` records an actual collision at 81 m; it is not evidence of a sustained successful wooded descent.

Final images in this directory were reviewed after the rock winding, caps, placement, and shadow corrections:

- `woods-study-482193-d650.png`
- `woods-study-482193-d2300.png`
- `woods-study-915772-d1150.png`
- `meadow-flight-752041.png`
- `stream-study-752041-d820.png`
- `summit-482193.png`

The woods and stream images marked **STUDY** are staged inspection views. The meadow image records an actual descent at 234 m. A still from actual play shows the rendered state at that instant; it does not establish input responsiveness or fairness throughout the run.

## Findings and resolved defects

The final images demonstrate a substantial improvement over the baseline. Larger bent trunks, exposed roots, variable branch and crown silhouettes, and grouped rocks give the woods more structure. The wooded views show more foreground terrain and less empty sky. The summit still distinguishes the open meadow, central watercourse, and denser woods through the landscape.

The squirrel has a continuous torso/head silhouette, small cupped ears, tapered limbs, slender digits, an attached gliding membrane, and a flattened tail. Its warm chestnut coloring remains readable against shaded ground. Random fur spikes no longer obscure its anatomy, and the intermediate stitched appearance of aligned coat locks is no longer prominent.

The following visible defects were identified and rechecked:

- **Hollow-looking rocks:** reversed side winding caused exterior-face culling and inward normals. Final rocks read as closed solid volumes with outward-lit faces. Cap winding was reviewed separately.
- **Ground ribbing:** the pronounced parallel artifacts visible in earlier wooded views are absent from the final captures.
- **Dark character shading:** manual gamma conversion compounded the Compatibility renderer's own conversion. Corrected materials restore readable body and tail form without reversing the already-correct loft normals.
- **Repetitive coat relief:** fewer staggered locks, varied dimensions, lower relief, and lower color contrast remove the conspicuous sewn pattern.
- **Floating distant scenery and dotted canopy lines:** neither is visible in the reviewed final images.

No major new rendering or visual-readability regression is apparent in the reviewed final stills. This conclusion is limited to these views and does not replace the final runtime checks.

## Remaining fidelity limits

The hardest woods still resemble a broad, relatively smooth green slope between placed assets. They are substantially less enclosed, irregular, and dominated by connected rocky terrain than the reference's steep forest ravine. The improvement should not be described as matching the reference.

Pine cards and rock contour patterns remain visibly procedural and stylized. Stream banks are easier to distinguish, but their densely repeated rows of stones look more landscaped than naturally eroded. Directional lighting produces readable warm surfaces and dark shadows, while lacking the reference's subtle filtered sunlight and layered atmospheric depth.

These remaining differences are material fidelity limits, rather than the broken rendering defects identified during the review. Demonstrations of beginner accessibility, advanced challenge, route crossings, collision fairness, and sustained generation belong to the separate flight and performance evidence.
