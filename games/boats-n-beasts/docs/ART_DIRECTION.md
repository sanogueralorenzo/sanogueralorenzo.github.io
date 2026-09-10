# Art direction

Use the [reef reference](island-reference.png) for islands and the [diorama reference](visual-restart/flat-diorama-reference.png) for boats, creatures and UI. References guide appearance; all gameplay art is generated in code.

- Keep water quiet and petrol-teal, with turquoise shallows and broken ivory surf.
- Use irregular sand coasts, soft grass transitions and readable groups of palms, slate rocks and ruins. Leave navigable gaps between islands.
- Derive terrain, shallows, collision and chart from one coastline. Use rounded outward offsets so underwater shelves survive concave bays; vary width smoothly, keep it positive and fade only the outer edge.
- Scale features with island size within sensible bounds. Keep full prop footprints behind the beach and treasure reachable from water.
- Boats are compact wooden pirate ships with cream sails, a readable dark flag and distinct hull colors. Keep weapons and health bars visible.
- Favor broad matte faces, restrained detail, warm light and cool shadows. Keep silhouettes and UI readable at gameplay scale.
- Share the camera projection across rendering, HUD and steering. Keep numerical tuning in code.
