# Redesign: larger islands, quieter interface, stronger characters

This revision addresses the user’s rejection of the original presentation. The earlier release’s small islands, dense HUD, sparse scenery, and assembled bird/ghost silhouettes were the starting point, not an accepted quality benchmark.

## Measured reference

The initial CozySora destination is **Seabreeze Village**, confirmed in its registry, source, and native project preview. Its walkable boundary is x ∈ [−118,118], z ∈ [−40,100], with a curved coastal exclusion. Sampling that horizontal boundary at one-metre cell centres gives **30,115 m²**. This is a boundary mask, not a claim that buildings, collisions, and the final height threshold leave every square metre traversable. Its 360×360 m render terrain includes ocean and background hills.

The final [16-island survey](island-survey.json), over seeds 1, 1701, 73919, and 2147483647, measures **26,452–36,116 m²**, averaging **30,609.75 m²**, using height > 0 at two-metre spacing. That is approximately −12% to +20% around the reference boundary area. The compared quantities are stated explicitly rather than presented as identical measurements. Main routes are roughly two dozen seconds of purposeful walking; side trails, fights, and return trips extend each visit.

## Before and after

| Area | Earlier release | Redesign |
|---|---|---|
| Interface | Permanent panels, crew cards, minimap and repeated labels | Health, gold and nearby actions; contextual chart/crew behind Tab; restrained title, choice and death screens |
| Island scale | Starter radius 48 m; variants 36–62 m | Starter radius 97 m; variants 90–105 m; coastline, relief, ridge spread and trail layout vary together |
| Voyages | 192 m placement cells; several shores close by | 3,200 m cells with offsets; new islands hidden beyond the fog/visibility boundary; measured crossings in the validation report |
| Terrain and routes | Single mound, central ramp, shrine plateau | Broad coast, wooded hills, valleys and saddles; main route and four branches; twelve rewards |
| Scenery | Sparse recovered trees and oversized faceted rocks | Actual Seabreeze trees, bushes, grass and leaf recipes; smaller selected recovered rocks; cleared discovery sites |
| Characters | Simplified bird/ghost bodies and slab hats | Actual CozySora cat anatomy/gait; pirate coats, tricorn and role equipment; articulated skeletal pirates retaining the recovered skull |
| Rendering | Per-triangle mesh upload, foreground obstruction | Background indexed generation, batched foliage, distant crowns, camera-to-subject leaf clearance |
| Pacing | All elapsed time increased pressure | Exploration and claimed shrines increase threat; open-water travel and chart inspection do not |

The visual reference is CozySora’s foliage, proportions, materials, and finish. Seabreeze itself is not copied wholesale into each island. Source geometry/recipes are directly adapted into this project; the island layout, relief, caches, and four-berth rules are authored here.

## Exploration and feedback

Eight trail pickups award 8 doubloons each. Four side trails end at a cairn, wreck, tent camp, and telescope lookout, permuted by seed. Their caches award 24 doubloons and visibly open when collected. Discovery props sit at sampled terrain height, with cleared space around them. The hollow bronze bell swings and sounds during its 24-second encounter. A countdown remains visible throughout that fight.

Captain and crew retain automatic attacks. Crew equipment identifies the six roles; attack events trigger a brief pose. Recovered A Short Hike body-bob/glide data remains active. Pirate monsters have readable caps, faces, articulated legs, cutlasses, and windups. Movement, attack timing, statuses, and rewards stay in the engine-independent core.

The island chart shows coast, paths, bell, landing, player and found caches while ashore. At sea it shows discovered/in-sight shores. The chart pauses gameplay; Escape closes it. The default 1920×1200 window, 1440×900 logical UI, and revised text scale improve Retina readability. Normal rendering targets 60 fps; movie timing is evaluated separately.

## Problems caught during iteration

Native play exposed and corrected a below-water landing on the third island, a diagonal boat approach that stalled near shore, oversized coastal rocks, subpixel leaf disappearance at distance, foliage hiding discoveries, floating/disconnected telescope legs, coins intersecting cache lids, an invisible old HUD strip blocking ground clicks, and encounter time advancing behind the chart. Coast-derived landings are now tested across 520 island/seed combinations. Actual path traversal is checked on non-starter islands as well as the first island.

Manual play verified ordinary sailing/disembarkation, click movement, jumping, camera tapping, auto-attacks, a side trail, cache payout/opening, chart inspection, and interaction range. Complete pilot runs use ordinary movement/combat/choice commands and are identified separately. Art-review views inspect each discovery site and all character roles; they are not presented as played runs.

See [native validation](VALIDATION.md) for exact final run outcomes, first-sighting times, frame pacing, local evidence, and remaining platform/recovery limits. See [provenance](PROVENANCE.md) for the concrete source translations and unrecovered material. Proprietary assets and all gameplay imagery remain local.
