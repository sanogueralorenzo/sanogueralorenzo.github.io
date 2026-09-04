# Cozy Sora design notes

Cozy Sora is an original procedural Godot implementation inspired by Japanese coastal summers and cozy exploration games. Its code, shaders, meshes, textures, animation, and audio are authored or generated specifically for this project. No external game assets or source code are bundled.

The coastal road connects rice paddies, a farm, a village, a wooded shrine, vending areas, and an elevated railway. Cat exploration offers a close view of the village; seagull flight reveals the landscape from above.

## World and movement constants

The coast centerline is `z = -12.5 - 0.0022 x² + 0.00001 x³`; road half-width is 4m. The inland loop reaches approximately ±57m east/west and z68m north. The shrine hill is centered at (0,30), with a 27m radius, 8m plateau radius and 8m height contribution. Paddies sit at elevation 0.4m, farm ground at 2.6m, and village ground at 3m. The elevated railway is at 11.5m and crosses the gully between x12 and x44.

The normal camera has a 62° vertical field of view. The cat begins at (-6.4, 0.2), with yaw −0.08 and pitch 0.09; camera follow distance is 4.2m. Cat walking/sprinting speeds are 3.6/6.4m/s, gravity 22m/s², and jump impulse 6.2m/s. The gull has 9.5/17m/s flight/boost targets, automatic gliding and ground perching, and a 4.5m flight follow distance.

## Procedural rendering

Godot meshes, shaders, collision bodies, particles, generated audio, and UI build the game at runtime. Procedural image routines create foliage, bark, timber, metal, roof tile, concrete, stone, and vending surfaces. GPU vegetation is grouped into spatial MultiMeshes. Static architectural primitives are merged without moving their collision bodies. Terrain and foliage caches contain only this project's generated output.

Forward+ lighting combines warm sunlight, cool ambient light, distance fog, and directional shadows. A painterly screen shader selects overlapping regions with low color variance to soften fine detail while retaining silhouettes. Procedural clouds, sea highlights, wind, butterflies, and drifting pollen animate the landscape.
