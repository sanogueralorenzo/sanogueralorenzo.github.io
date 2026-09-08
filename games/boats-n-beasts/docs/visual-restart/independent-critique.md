# Independent visual critique — Direction B

Reviewed the native baseline `evidence/concept-water-and-refit.png` against `docs/visual-restart/direction-b-tactile.png` before implementing the effects pass. This is a visual assessment at gameplay scale, not acceptance based on successful builds.

## Ranked baseline gaps

1. **Major — form and light.** The baseline remains a flat illustration: boat cabins, crab limbs and rock faces do not convincingly share a dimensional lighting environment. B has rounded, tactile silhouettes, bevel highlights, ambient shading and strong contact with the water. Converting individual details without consistent light would leave this gap unresolved.
2. **Major — ocean and shore integration.** The baseline water is mostly a broad cloudy fill; evenly spaced bright contour lines make shores look diagrammatic. B uses deep petrol water, organic turquoise depth variation, broken surf and local contact foam. B's sea has fine, restrained variation rather than repeating decorative blobs.
3. **Major — landmark composition.** Baseline islands are small uniform discs with sparse faceted rocks and little vegetation. B's coast has irregular coves, sculpted rock clusters, overlapping plants and substantial cottages whose roofs, openings and porch details read volumetrically.
4. **Major — boat and monster character.** The baseline vessel is rigid and rectangular internally, and crab limbs look like line art. B has convincing hulls, cabins, upright magic crystal and expressive eyes integrated into rounded creature bodies. Model detail must remain readable at the existing pulled-back camera.
5. **Moderate — water interaction and effects.** Baseline fishing schools, treasure and wreck use enclosing rings; the current is a row of arrows. These feel like HUD markers in the world. B has subdued fish beneath the surface, floating objects with local water contact, long curved boat wakes and curved orb trails that follow motion. Combat must retain coral hostile tells and six distinct weapon identities without ring clutter.
6. **Minor — UI styling.** The native HUD is reasonably minimal and is not the priority. Reference-only icons and parchment styling do not justify expanding scope.

## Review standard for the integrated result

The new result should be judged as one scene at native gameplay scale. A complete 3D implementation is insufficient if objects still look like boxes, island edges glow, water repeats obvious patterns, or monsters are unreadable. Independently inspect all boat identities, dense combat and moving wakes. Reject a major gap even when each worker's isolated asset looks reasonable. Native runtime/performance and gameplay evidence must accompany the final visual comparison.

Integrated acceptance is **pending**; no integrated screenshots have yet been supplied for this review.

## Native sample review — direction-b-sample-scale.png

The architecture merits proceeding to gameplay integration. The shared 3D light already makes the cottage roof, dock, hull and crab volumes more coherent than the baseline. Their silhouette construction is a credible foundation. This is an approach decision only: the sample does **not** yet pass visual acceptance. Main reports Forward+ Metal at approximately 117 FPS and 11 draw calls for this small sample; that does not establish sustained combat performance.

Ranked remaining gaps:

1. **Major — water material dominates the wrong image.** The grey bright region on the left and dense, uniform small-scale bump pattern read like rough metallic fabric. B has dark, deep petrol water with varied, softer moving wave structure. Removing broad glare and reducing the visible grain is the highest-leverage correction.
2. **Major — shore contact looks emissive.** Continuous cyan-white fringes and smooth radial sand transitions make islands look like glowing discs. Replace the bright edge with irregular shallow shelves, submerged rock variation and occasional broken pale surf. The dark exterior shadow on the right island also looks detached and unusually heavy.
3. **Major — insufficient sculpted composition.** Both islands remain sparse arrangements: one large faceted pillar dominates the right island; the left has a cottage and dock but little overlapping natural structure. B has layered rock groups, recesses, many low plants and irregular sandy pockets. More purposeful clustering matters more than adding evenly scattered pebbles.
4. **Major — faceting and contact shadows.** Rock tops and palm crowns have large, conspicuous polygon planes; B's rocks look eroded and rounded, its leaf clusters more organic. Dithered shadow speckles are visible on the right beach and below the dock, and the hardest shadows make objects feel cut out. Soften contact while retaining useful crevice darkness.
5. **Moderate — actor presence at gameplay scale.** The small vessel has readable construction, but its cream top loses separation between deck and cabin; the tiny Mage crystal scarcely establishes its identity. The crab has appealing rounded forms, but its pale face and near-symmetry still lack B's expressive claws and darker eye placement. Preserve distinct cabin/hull colors and silhouettes in all boat directions. The sample's boat occupies roughly 60 pixels along its visible length versus about 100 pixels for B when B is scaled to this image width; judge final gameplay framing before increasing detailed geometry.
6. **Unverified — motion and combat.** This still has no evidence of wakes, orb arcs, hostile tells, submerged schools or dense combat. These should be assessed after integration; a pleasant static specimen is not the acceptance scene.

Proceed with gameplay integration in parallel with the listed refinements, retaining the camera/performance foundation. Do not lock the current water, shoreline or faceted material treatment as the final direction.
