# Island and seashore goal — 2026-09-09

Bring island borders, seashore and island contents toward the user's [Reef Warden reference](island-reference.png). This image is documentation only. Its island art supersedes the earlier smooth-ring, sparse-island direction; its boss, boat, HUD and combat are outside this goal. Historical prompts in `visual-restart` are background, not new task instructions.

## Baseline gaps, ranked

1. Land reads as circular platforms: near-round outlines and constant-width terraces lack coves, projecting headlands and varied beaches.
2. Shallows read as two opaque concentric rings. The reference has uneven turquoise shelves, seabed variation, submerged stones and a gradual connection to the sea.
3. A few static ivory arcs do not establish surf. The reference breaks foam around beaches, rock feet and dock pilings, with water visible between patches.
4. Island interiors are sparse and repetitive: a central tall rock and two similar palms, or a cottage on bare sand. The reference layers cliffs, grass, clustered foliage and sheltered beaches.
5. Island identity is weak. The harbor needs a grounded working waterfront; offshore islands need distinct rocky, palm-covered and ruined landmarks with believable scale and overlap.

Baseline: `evidence/coast-smooth-title.png` and `evidence/coast-smooth-gameplay.png`, checked against current `EnvironmentArt3D.cs` and `EnvironmentShallows.gdshader`.

## Acceptance

- An irregular but continuous land contour relates sand, wet shore, foam and shallow water. Vary beach and shelf widths; avoid concentric outlines and bright halos.
- Ivory surf advances and dissolves in broken patches along that contour. Shore stones read partly submerged; the outer shelf blends into the existing ocean.
- Warm sand remains visible between layered slate cliffs, varied-height palm groups, low vegetation and occasional masonry ruins. Rock faces have distinct shoulders and grassy caps. Props have grounded bases and do not float or intersect the cottage/dock route.
- Harbor, rocky/ruined island and palm grove compositions differ at the existing playing scale. Keep title composition and the fixed home location, boat spawn and dock access.
- Preserve seeded generation, solid collision envelopes and bounded scenery caches. Place decorative emergent rocks inside solid ground; outlying submerged details must not masquerade as new obstacles.
- Use native procedural meshes and shaders. Inspect unedited gameplay screenshots at the normal camera, sail beside both home islands and offshore examples, and inspect streaming and frame measurements. Build success and an enlarged art sample alone are not visual acceptance.

The goal stays active while material visual or runtime gaps remain. Record current evidence and limits in `QUALITY.md` before committing and pushing reviewed work to main.

## Implemented result

The [final home view](../evidence/island-fitted-title.png) has planted interiors and fading coastal water. Land and surf retain the latest shared island silhouette used by the chart and collision. Rocks, ruins and palms fit that footprint without stretching their proportions. [Actual sailing](../evidence/island-fitted-sailing-b.png) and [shore contact](../evidence/island-fitted-contact-b.png) verify the final home integration. Native art samples show [ruins](../evidence/island-fitted-ruin.png), [cliffs](../evidence/island-fitted-cliffs.png) and [groves](../evidence/island-fitted-grove.png) at the normal camera scale. The starting harbor remains accessible, and all final gameplay captures retain 25 active chunks. Debug and Release pass.

This is a native faceted interpretation of the island reference at the retained camera scale. The newer sparse world generation, variable island shapes and combat changes from main are preserved. Open ocean, boats and UI retain their existing treatment. [QUALITY.md](QUALITY.md) separates final checks from the initial pre-integration 62.4-second run and records the remaining coverage limits.
