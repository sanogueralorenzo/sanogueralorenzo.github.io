# Art direction

Use the [reef reference](island-reference.png) for island shores and interiors, and the [diorama reference](visual-restart/flat-diorama-reference.png) for boats, creatures, water and UI. References are documentation, not gameplay assets or requests for new mechanics.

- Keep open water quiet and petrol-teal. Fade mottled turquoise shallows into the sea; use broken ivory surf instead of opaque rings.
- Use irregular warm sand coasts with broad curved bays. Avoid abrupt straight edges, narrow V cuts and needle headlands. Terrain, shallows, surf, props, collision and chart must share the coastline.
- Mix eight silhouettes: compact, long, crescent, lobed, headland, bean, twin and scalloped. Radius bands are 80–115, 165–235, 290–360 and 520–720, with candidate weights 35/35/15/15%. Radius is the longest land reach.
- Fill larger interiors with more palm, shrub and slate-rock groups; retain familiar prop proportions and bounded beach/shelf depths. Distinguish ruins, cliffs and groves. Keep dock paths and boat approaches clear.
- Scatter landmarks sparsely with navigable gaps and no visible chunk grid. Treasure has a 15% island candidate chance; barrels have a 20% chunk candidate chance and at least 900 units between them. Clearance rejection reduces actual density. Keep chests reachable from water, barrel markers absent, and reward feedback brief and local.
- Use matte broad faces, restrained bevels, warm light and cool shadows. Preserve readable boat/monster silhouettes, violet friendly magic and coral hostile bombs. Wakes follow actual motion; fish stay submerged without overhead markers.
- Use cream text, navy panels, turquoise controls and visible keyboard focus. Avoid fine surface noise and ornamental UI clutter.

`StartingArea` owns the real title and voyage scene: cottage upper-left, island lower-right, selected boat at `(55,-315)` alongside the dock. Set Sail fades the menu; movement waits for input and camera follow begins after departure.

Simulation `(x,y)` maps to native `(x/100,0,y/100)`; bows point along -Z. Preserve orthographic scale 0.74 pixels per simulation unit and 0.84 ground-plane foreshortening. HUD projection and sailing clicks use the same camera.

Compare at normal playing scale. `./run.command art-sample.tscn` opens a separate visual sample without a Voyage: Tab changes inspection scale, Space cycles families, V changes variant, R selects radius 95/200/330/720, and F12 captures. Confirm collision, access and streaming in actual gameplay as described in [QUALITY.md](QUALITY.md).
