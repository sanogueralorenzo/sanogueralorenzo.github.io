# Island size and shape variety — 2026-09-09

Make islands visibly different in size and silhouette at the normal playing camera, building on the [completed reef art goal](ISLAND_GOAL.md) and its [reference](island-reference.png).

## Baseline

The current islands all use one bent elliptical outline. Radius parameters range from 110 to 290, but both the ellipse and coastline formula shrink the result; many islands still look like similar small beans. The [previous cliff sample](../evidence/island-fitted-cliffs.png) shows the issue beside the fixed 140-radius harbor.

## Acceptance

- Offshore generation mixes small islets, medium islands and occasional substantial landmasses. Actual footprints clearly differ beside the same boat and camera; radius values describe the longest land reach.
- Compact, long, crescent, lobed and headland profiles have recognizable silhouettes, with seeded rotation, asymmetry and small coastal variation. Interior composition varies independently of profile.
- Land, beach, surf, chart and collision use the same simple continuous outline. Coves remain navigable up to the boat's real clearance. Palms, rocks and ruins stay grounded and retain their proportions on narrow land.
- Keep sparse open seas, deterministic chunk generation and bounded caches. Increase landmark spacing where large landmasses need it. Preserve the home harbor, dock access, spawn and normal camera.
- Inspect all five families and three size bands in the native art sample. Check actual gameplay shoreline contact, offshore discovery and streaming. Record focused Debug/Release builds, native evidence and coverage limits in `QUALITY.md` before committing and pushing to main.

## Implemented and verified

Offshore candidates now use radius bands 80–115, 165–235 and 290–360 with 35%/43%/22% weights. Five seeded profiles replace the single bent ellipse. Normalizing each outline makes the chosen radius its actual longest reach; it no longer gets reduced by the shape formula. The 128 positive radial samples form a simple polygon shared by scenery and collision. Profile selection uses a mixed seed, while ruins, groves and cliffs retain their separate style selection.

Landmark spacing is the greater of 900 units and the sum of both solid bounds plus 320 units. At the maximum radius this stays below 1,069 units, so the existing eight-neighbor check covers every possible conflict (candidates two chunks apart are at least 1,400 units apart). The fixed harbor, spawn and camera remain unchanged.

The [native sample matrix](../evidence/README.md) compares all five families at radii 95, 200 and 330 beside an unchanged boat and harbor. The first crescent was too shallow and the first headland too similar to a long island; both were refined before the final review. Actual gameplay verifies dock access, stable home shore contact, an offshore crescent, a headland and streaming through 57.8 seconds. [QUALITY.md](QUALITY.md) records measurements and limits. Debug and Release pass with zero warnings/errors.

## Follow-up: more diversity and fewer abrupt lines

The user reported abrupt lines after the first variety pass. Inspection found tight V-shaped crescent inlets and steep headland transitions; changing rotation alone also left too many similar silhouettes.

Eight equally weighted families now include curved beans, connected twin lobes and four/five-scallop shores. Seeded width, lean, rotation, relief and guide offsets vary each family. A periodic cubic B-spline rounds 16 coastal guides, including the closing seam. It uses positive weights without overshooting its neighboring guides. The curve is sampled back onto 192 radial points for the existing nested terrain layers, props, chart and collision, then normalized to the selected radius. Crescent guides use a broad rounded back to the bay; headlands have smooth broad shoulders. The size bands, landmark spacing, home harbor, camera and gameplay rules are retained.

The first revised bay still looked pointed in the native renderer, and initial bean/twin samples were too close to ovals. Those were corrected before the final eight-family review. Additional crescent, bean and twin seeds establish variation within families; small/medium crescent and twin samples check prop fitting. Actual gameplay checks home shore contact, a 218-radius twin island, a 293-radius long island and 25-chunk streaming through 54.8 seconds. The [latest evidence](../evidence/README.md) and [quality notes](QUALITY.md) supersede the earlier pass's appearance and measurements.
