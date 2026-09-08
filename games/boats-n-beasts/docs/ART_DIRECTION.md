# Approved visual direction

Reference: `/Users/mario/.codex/generated_images/01a07e8b-d952-7933-a719-c16d3272bb62/exec-45a0965f-d508-4b73-b690-4718a324b8f9.png`.

## Requirements

- Preserve the pulled-back near-overhead camera, spacious sailing lanes and compact HUD.
- Petrol-blue sea: broad, restrained depth bands, subtle moving surface detail and sparse glints.
- Land-connected turquoise shallow shelves, broad warm beaches, restrained animated surf, sage vegetation and one dominant landmark rather than piles of rocks.
- Readable shaded boat hulls with distinct equipment and identity: gun turret, Aura's turquoise deck mechanism, Mage's prominent upright violet crystal.
- Curved boat wakes with broken foam accents; short creature wakes and contact shadows that connect subjects to the water.
- Rounded, faceted creature forms and expressive faces, with silhouettes clear against the sea.
- Violet homing orbs with curved trails, dimensional treasure/glints, and submerged-looking fish schools. Coral hostile attacks remain visually dominant over friendly effects.
- Original procedural C#, shaders and engine primitives only. The approved image guides the work and is not shipped as game art.

## Acceptance and verification

Compare native captures with the reference at normal camera scale. Check moving boats, shorelines, fish visibility, creature rendering and combat readability. Build Debug and Release; inspect runtime logs for rendering errors and capture frame timings. Preserve combat, progression, collision, generation, controls and the two-weapon limit.

Implemented in the reference visual pass: world-anchored depth fields; land-shaped transparent shelves; broad beaches, plants and sparse sand detail; upright Mage crystal; shaded shells and larger serpent art; bounded trail histories; animated surf and foam; treasure shading and fish shadows. Scenery is drawn with premultiplied alpha so cached translucent shelves remain turquoise rather than darkening the water.

Native comparison captures are in `evidence/concept-style-combat.png` and `evidence/concept-style-motion.png`. The procedural result remains more graphic and has less surface microdetail than the generated illustration; foam is deliberately restrained for gameplay readability. The latest ray-body and sparse sand-grain refinements follow those captures.
