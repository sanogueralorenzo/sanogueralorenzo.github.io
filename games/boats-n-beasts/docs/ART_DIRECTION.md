# Art direction

Use the [reef reference](island-reference.png) for island shores and interiors, and the [diorama reference](visual-restart/flat-diorama-reference.png) for boats, creatures, water and UI. Use these as visual references only.

- Keep open water quiet and petrol-teal. Fade mottled turquoise shallows into the sea; use broken ivory surf instead of opaque rings.
- Use irregular warm sand coasts with broad curved bays. Avoid abrupt straight edges, narrow V cuts and needle headlands. Terrain, shallows, surf, props, collision and chart must share the coastline.
- Reserve a modest, seeded-width dry beach using distance to the nearest coastline edge, not radial scaling. Build underwater shelves from rounded outward coastline offsets so bays cannot collapse their geometry. Scale shelf width with island size and vary it smoothly along coastline length, with a positive minimum width. Keep the inner shallows visible everywhere and fade only the outer edge; do not punch transparent holes into the shelf. Diffuse sand through dry grass into green with broad, low-contrast procedural variation rather than a narrow contour-following color border. Keep full rock, ruin, shrub and palm-crown footprints behind that reserve; shrink or omit props that cannot fit. Narrow spits may remain sand-only.
- Mix compact, elongated, crescent, lobed and scalloped silhouettes, from small islets to occasional giant islands. Size bands and placement weights live in `OceanWorld.cs`; outlines live in `IslandShape.cs`.
- Fill larger interiors with more palm, shrub and slate-rock groups; retain familiar prop proportions and bounded beach/shelf depths. Distinguish ruins, cliffs and groves. Keep dock paths and boat approaches clear.
- Scatter landmarks sparsely with navigable gaps and no visible chunk grid. Keep chests reachable from water, barrel markers absent, and reward feedback brief and local.
- Boats are compact wooden pirate ships with raised ends, an open foredeck, a low sterncastle, a billowing cream square sail, a straw-hat skull emblem and a ram figurehead. A tall mast carries a broad dark skull-and-crossbones pennant; keep the health bar above it. Build every part in C# geometry; keep navy/turquoise/violet hull bands for Gunboat/Aura/Mage, and leave both weapon fittings visible.
- Use matte broad faces, restrained bevels, warm light and cool shadows. Preserve readable boat/monster silhouettes, violet friendly magic and coral hostile bombs. Wakes follow actual motion; fish stay submerged without overhead markers.
- Use cream text, navy panels, turquoise controls and visible keyboard focus. Avoid fine surface noise and ornamental UI clutter.

`StartingArea` owns the real title and voyage scene: cottage upper-left, island lower-right, selected boat alongside the dock. Set Sail fades the menu; movement waits for input and camera follow begins after departure.

Simulation `(x,y)` maps to native `(x/100,0,y/100)`; bows point along -Z. Preserve orthographic scale `0.74 / 1.40` (about 0.5286) pixels per simulation unit and 0.78 ground-plane foreshortening (about 51° above the water). The shared boat scale is enlarged by 80% from its original proportions so its flag and fittings stay readable in the view, which shows 40% more world along each axis than the original 0.74 zoom. HUD projection and sailing clicks use the same camera.

Compare at normal playing scale. `./run.command art-sample.tscn` opens a separate visual sample without a Voyage: Tab changes inspection scale, Space cycles families, V changes variant, R selects radius 95/200/330/720, B toggles the shoreline regression island (radius 355.70514, seed 2273309013), and F12 captures. Confirm collision, access and streaming in actual gameplay as described in [QUALITY.md](QUALITY.md).
