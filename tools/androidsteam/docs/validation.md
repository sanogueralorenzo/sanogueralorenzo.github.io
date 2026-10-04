# Device validation

Validated on Samsung S24 SM-S921U1, Android 16/API 36, Snapdragon 8 Gen 3/Adreno 750. These results cover this device and configuration.

## Superflight baseline

- Steam app ID: `732430`, launched by Steam through `steam://rungameid/732430` and the client’s Play button.
- Compatibility: **Android Steam Proton (ARM64)**, using Steam-managed **Proton Experimental (ARM64)** app `4427310`, build `25646942`, depot manifest `1476754387216214045`, version `1790839316 experimental-11.0-20261001-arm64`.
- Launch options: `-force-d3d11 -screen-width 1280 -screen-height 720 -screen-fullscreen 1`.
- Runtime: Ubuntu Minimal 26.04 ARM64 release `20261002`; session bundle 10, Gamescope 3.16.20, XWayland 24.1.10; matched Turnip/Mesa pins in THIRD_PARTY.md.
- The tool calls Valve’s ARM64 Proton without the namespace container Android refuses. Wine receives only the required Android adapters; native Steam overlay injection is excluded. A narrowly scoped helper preserves executable private Wine image mappings when Android rejects file execmod.

The actual Wine command line confirmed the selected executable and arguments after Steam restart. Debug and minified release builds reached flight, responded to held keyboard steering, and exercised collisions/retry. Debug gameplay showed a proximity combo increasing to 72. Two consecutive launches and clean game exits passed in each build while the primary Steam process stayed alive. Login, installed games and saves were retained. Audio, complete touch/controller input and arbitrary game/tool compatibility remain unvalidated.

## Initial release measurements

Workload: animated Superflight menu, D3D11, 1280×720 fullscreen, native overlay excluded, minified release signed with the development key. This establishes a reference; it does not demonstrate a speed improvement or sustained gameplay frame rate.

| Measurement | Result |
| --- | --- |
| Aggregate app UID PSS | 2335.8 MiB |
| CPU median, three 5-second samples after discarding the first `top` sample | 267.6% of one CPU core |
| SurfaceView presentation rate, approximately 45.9 seconds | 34.32 FPS |
| Presentation intervals | 553 at 16 ms; 829 at 33 ms; 191 at 50 ms; 2 at 66 ms |

Use `dumpsys meminfo` for each UID process, `top -b -n 4 -d 5 -u <uid>`, and SurfaceFlinger timestats for the actual SessionActivity SurfaceView. Presentation rate measures Android frames, not Unity engine FPS. Launch latency and sustained gameplay need separate measurements.

## Focused checks

Debug/test/minified-release assembly, lint and 13 unit tests passed. Eight opt-in S24 Steam/Wine/lifecycle checks passed, including packaged dependencies, executable Wine memory behavior and Home/resume/stop cleanup. The shipped PRoot matches the normal pinned build; temporary crash diagnostics are excluded.

Read only bounded game/process logs for launch, arguments and exit status. Authentication logs and credential-bearing Steam configuration are outside diagnostics. Use the README’s ADB instrumentation runner to preserve user data.
