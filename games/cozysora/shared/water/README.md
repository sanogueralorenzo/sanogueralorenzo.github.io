# Shared water

All visible water uses this component: the Seabreeze and Harbor seas, Seabreeze rice paddies, and Daan’s ecological pond. Each surface is a live child of its map, created outside the static scene cache and freed with the gameplay session. No downloaded visual or audio assets are used.

## Source and adaptation

The implementation was informed by direct inspection and native-browser play of [Sunwake: The Last Light](https://sunwake-the-last-light.openai.chatgpt.site/), including its deployed `assets/index-47cw1oNL.js` bundle on September 7, 2026. Its natural-ocean mode is the reference. The JavaScript is not bundled or copied into this project. The algorithms and parameters were translated into original C# and Godot shader code.

The deployed code has **24 geometric wave components**, despite comments referring to eight: four directional families, four rotated companions, and sixteen seeded JONSWAP-like spectral components. The translation retains the source wavelengths, speeds, phases, directional spreads, energy bands, gravity constant, seed and hash mixing. Per-surface amplitude, wavelength scale and calm/swell blend adapt this spectrum to each setting.

The dense near grid spans 216 m with 192 divisions. Stitched square rings expand to radii 210, 520, 1150 and 2920 m with decreasing segment counts. Unequal rings share stitched edges, and matched quads alternate diagonals. Short geometric waves fade as the grid becomes coarser. Beyond the dense region, analytic fragment normals and crest shading prevent the broad aerial views from exposing interpolated triangles. The mesh follows the camera; phases remain in world space.

The material translates six normal-only capillary/gravity octaves, wavelength/derivative filtering, air/water Fresnel (F0 0.02037), Beer–Lambert absorption, crest scattering, fine satin detail and a bounded, footprint-filtered GGX sunlight lobe. Small phase advection and normal-variance roughness keep the sheltered profiles from producing ruled ripple patterns or unresolved sparkling. Godot supplies the current map’s filtered sky radiance, actual lights and shadows. Daan retains its existing screen-space reflections.

This is a water rendering and support component for Cozy Sora’s persistent summer settings. Sunwake’s 148-second storm/surge cycle, exceptional hero-wave packets, sailing hull/wake simulation, headlamp, celestial clock and story events are not part of these maps. Fixed map profiles intentionally preserve the existing weather and gameplay. The result is not claimed to reproduce the entire Sunwake simulation.

## Ownership

| File | Responsibility |
| --- | --- |
| `WaterSpectrum.cs` | Engine-independent C# wave construction and height, slope, displacement and vertical-velocity queries using `System.Numerics` |
| `WaterMesh.cs` | Engine-independent C# grid/ring geometry and triangle indices |
| `CozyWaterProfile.cs` | Godot resource adapter exposing map-owned wave and optical settings |
| `CozyWaterSurface.cs` | Godot node adapter, generated mesh and 257² floating-point bathymetry texture, shared simulation clock and uniform upload |
| `CozyWaterFloat.cs` | Godot adapter for anchored boats and buoys, sampling height and tilt across the shared surface |
| `water.gdshader` | Matching geometric displacement plus water optics and view-filtered fine surface detail |

`CozyAtmosphere` installs a coastal surface when `OceanEnabled` is true. Maps instantiate shallow surfaces directly with their bounds, mean level and terrain sampler. Profiles live in `maps/<id>/water.tres`; Seabreeze also owns `paddy_water.tres`. Shared code contains no map-ID branches.

Bathymetry fades smoothly to deep water before the coastal texture’s outer boundary. CPU bilinear sampling and GPU texel-center sampling use the same transition. Shore depth damps geometric displacement; pond and paddy clipping uses the map’s generated depth field. Sea bounds and mean levels remain authored by the map.

The seagull queries this same spectrum and clock. Four fixed-point iterations invert horizontal Gerstner displacement before returning the surface height, so a settled gull follows the rendered waves. Harbor’s moored boats and buoys also sample the shared surface; their generated geometry is cached, while live float adapters are installed after restoration. Solid roofs and decks keep priority. Unsafe cat switches retain the existing dry-ground recovery policy. Water animation pauses with the gameplay session, without a separate wall clock or global shader time.

## Runtime review

Build and launch through `run.sh`. Use the project README’s scenic captures and ordinary `--pose` cameras. Inspect both coastal horizons from water level and flight, Daan’s deck and pond, and the rice paddies. Check gull settling/takeoff, pause/resume, safe cat recovery and destination changes. Verification is native rendering and play; no automated tests are included. See the project’s `VERIFICATION.md` for recorded observations.
