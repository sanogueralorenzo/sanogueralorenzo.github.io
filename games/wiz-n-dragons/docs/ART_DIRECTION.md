# Art direction

Match the broad matte forms, soft warm light, cool shadows, cream text and petrol-teal palette of Boats 'n' Beasts. Friendly spells are violet/turquoise; hostile magic is coral. Wizards wear pointed hats and ride wooden brooms. Dragon wings flap; spell choices add visible orbiting crystals to the wizard miniature.

The sky is open in every direction. Clouds are decorative, never terrain. Three independently scrolling layers give near clouds stronger parallax than distant clouds. Keep cloud caches bounded and placement deterministic by seed and cell. Deeper layers use darker, quieter colors so combat remains readable.

All gameplay art is procedural C#/Godot geometry and shaders. Generated concept images are visual references, not runtime assets.

Background atmosphere uses warped, multi-octave cloud banks, directional highlights and three independently scrolling shader layers. Sculpted clouds are sparse, tapered banks with small edge curls rather than dense piles of spheres. Keep the central flight space readable; use restrained contrasts without flashing lightning.
