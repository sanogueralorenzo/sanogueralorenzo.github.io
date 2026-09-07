# Shared water

All visible water uses this component: the Seabreeze and Harbor seas, Seabreeze rice paddies, and Daan’s ecological pond. Each surface is a live child of its map, created outside the static scene cache and freed with the gameplay session. No downloaded visual or audio assets are used.

## Source and adaptation

The implementation was informed by direct inspection and native-browser play of [Sunwake: The Last Light](https://sunwake-the-last-light.openai.chatgpt.site/), including its deployed `assets/index-47cw1oNL.js` bundle on September 7, 2026. Its natural-ocean mode is the reference. The JavaScript is not bundled or copied into this project. The algorithms and parameters were translated into original C# and Godot shader code.

The deployed code has **24 geometric wave components**, despite comments referring to eight: four directional families, four rotated companions, and sixteen seeded JONSWAP-like spectral components. The translation retains the source wavelengths, speeds, phases, directional spreads, energy bands, gravity constant, seed and hash mixing. Per-surface amplitude, wavelength scale and calm/swell blend adapt this spectrum to each setting.

The dense near grid spans 216 m with 192 divisions. Stitched square rings expand to radii 210, 520, 1150 and 2920 m with decreasing segment counts. Unequal rings share stitched edges, and matched quads alternate diagonals. Short geometric waves fade as the grid becomes coarser. Beyond the dense region, analytic fragment normals and crest shading prevent the broad aerial views from exposing interpolated triangles. The mesh follows the camera; phases remain in world space.

The material translates six normal-only capillary/gravity octaves, wavelength/derivative filtering, air/water Fresnel (F0 0.02037), Beer–Lambert absorption, crest scattering, fine satin detail and a bounded, footprint-filtered GGX sunlight lobe. Small phase advection and normal-variance roughness keep the sheltered profiles from producing ruled ripple patterns or unresolved sparkling. Godot supplies the current map’s filtered sky radiance, actual lights and shadows. The material uses the map’s depth-fog color, range and curve through Godot’s final fog stage. The dielectric adapter uses `SPECULAR = sqrt(0.02037 / 0.16)` to match Forward+’s squared reflectance mapping. Daan retains its existing screen-space reflections.

This is a water rendering and support component for Cozy Sora’s persistent summer settings. Sunwake’s 148-second storm/surge cycle, exceptional hero-wave packets, sailing hull/wake simulation, headlamp, celestial clock and story events are not part of these maps. Fixed map profiles intentionally preserve the existing weather and gameplay. The result is not claimed to reproduce the entire Sunwake simulation.

## Harmony with the summer maps

The follow-up keeps the geometric spectrum and support behavior intact. It improves how those waves read within the maps:

- The map’s depth-fog curve attenuates the final water lighting, including reflections. The former independent 280–2300 m sea-haze ramp left saturated water beside fogged-out terrain. A map-owned middle-distance opacity retains water identity where the elevated Seabreeze road otherwise overlooks an opaque white field. The bound fades away for cameras 50–100 m above the surface and for water 1.15–4 times the map fog-end distance away, preserving full aerial and horizon haze. Harbor, pond and paddies use the full map fog range without that bound.
- A deterministic, seamless two-channel C# texture supplies slow wind patches and smaller shoreline breakup. Quintic interpolation and multiple periodic scales produce gentle gust regions; mipmaps filter their distant appearance. The normal-only ripples remain phase-continuous and leave quieter areas between patches. This field follows the paused simulation clock, not shader `TIME`.
- A separable squared Euclidean distance transform measures distance to wet and dry terrain samples in world meters. Their signed combination interpolates across the rasterized bank. A narrow, irregular color transition softens shoreline contact even in Daan’s almost-flat pond; sparse moving foam is reserved for the coast. Paddies also measure distance to their authored rectangular bounds. This is a shading field, not a change to terrain, collision or water support.
- Map-owned roughness, modestly muted coastal body colors, quieter crest scattering and a lower direct-sun peak retain readable broad swells without making the sea the hardest, brightest material in the scene. Harbor remains sheltered, Seabreeze more open, the pond mossy and still, and paddies almost motionless and foam-free.

Technique references: [GPU Gems, Effective Water Simulation from Physical Models](https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-1-effective-water-simulation-physical-models) describes separate geometric and normal-detail scales and analytic wave derivatives. [Felzenszwalb and Huttenlocher, Distance Transforms of Sampled Functions](https://cs.brown.edu/people/pfelzens/papers/dt-final.pdf) describes separable lower envelopes for distance transforms; this project implements the algorithm in original C#. [Godot’s Forward+ lighting source](https://github.com/godotengine/godot/blob/master/servers/rendering/renderer_rd/shaders/scene_forward_lights_inc.glsl) defines the dielectric reflectance mapping. No reference code or assets are bundled. The fog calculation follows [Godot 4.7.2’s depth-fog and custom-fog stages](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl), with the bounded low-camera adaptation described above.

The shore field follows the resolution of the generated bathymetry; it cannot add detail to the authored terrain silhouette. Wind fields affect shading only, so they do not add a second buoyancy simulation. The existing adaptive wave mesh and footprint filtering avoid the cost of an FFT ocean or a fluid solver for these calm, fixed-weather maps.

## Ownership

| File | Responsibility |
| --- | --- |
| `WaterSpectrum.cs` | Engine-independent C# wave construction and height, slope, displacement and vertical-velocity queries using `System.Numerics` |
| `WaterFields.cs` | Engine-independent signed shore-distance transform and periodic wind/breakup field generation |
| `WaterMesh.cs` | Engine-independent C# grid/ring geometry and triangle indices |
| `CozyWaterProfile.cs` | Godot resource adapter exposing map-owned wave and optical settings |
| `CozyWaterSurface.cs` | Godot node adapter, generated mesh and 257² floating-point bathymetry/shore textures, mipmapped 128² RG wind field, shared simulation clock and uniform upload |
| `CozyWaterFloat.cs` | Godot adapter for anchored boats and buoys, sampling height and tilt across the shared surface |
| `water.gdshader` | Matching geometric displacement plus water optics and view-filtered fine surface detail |

`CozyAtmosphere` installs a coastal surface when `OceanEnabled` is true. Maps instantiate shallow surfaces directly with their bounds, mean level and terrain sampler. Profiles live in `maps/<id>/water.tres`; Seabreeze also owns `paddy_water.tres`. Shared code contains no map-ID branches.

Bathymetry fades smoothly to deep water before the coastal texture’s outer boundary. CPU bilinear sampling and GPU texel-center sampling use the same transition. Shore depth damps geometric displacement; pond and paddy clipping uses the map’s generated depth field. Sea bounds and mean levels remain authored by the map.

The seagull queries this same spectrum and clock. Four fixed-point iterations invert horizontal Gerstner displacement before returning the surface height, so a settled gull follows the rendered waves. Harbor’s moored boats and buoys also sample the shared surface; their generated geometry is cached, while live float adapters are installed after restoration. Solid roofs and decks keep priority. Unsafe cat switches retain the existing dry-ground recovery policy. Water animation pauses with the gameplay session, without a separate wall clock or global shader time.

## Runtime review

Build and launch through `run.sh`. Use the project README’s scenic captures and ordinary `--pose` cameras. Inspect both coastal horizons from water level and flight, Daan’s deck and pond, and the rice paddies. Check gull settling/takeoff, pause/resume, safe cat recovery and destination changes. Verification is native rendering and play; no automated tests are included. See the project’s `VERIFICATION.md` for recorded observations.
