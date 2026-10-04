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

## Arch ARM migration

The replacement is assembled from 239 checksum-pinned packages, with kernel/firmware, development outputs and manuals excluded. Steam still requires GTK2; two Debian libraries are pinned separately. Two independent builds produced identical 160638848-byte archives (153.2 MiB), SHA-256 `858d380e199e53e2ceff5790a77a7e5c7c4393ab1b8083f4353fbc652a660204`. Package/source locks and build scripts define updates; users install one tested replacement bundle, preserving their separate home.

Installed before session startup: runtime 788.7 MiB, adapters 0.057 MiB, graphics 28.0 MiB; total 816.7 MiB. The corresponding Ubuntu root/components/graphics baseline occupied 827.5 MiB. LLVM remains about 161 MiB because the packaged Mesa libraries depend on it. Compressed size alone is not a performance measurement.

The final snapshot uses GNU libc 2.43, Gamescope 3.16.31, XWayland 24.1.13 and SDL 3.4.16. Real Steam startup exposed two gaps that ELF checks missed: Valve's browser script requires `taskset`, and SDL recreates its shell role on the same Wayland surface. Added util-linux and its real invocation to the dependency check; reset the old shell configure serial on destruction. A repeated same-surface remap check failed before that reset and passed afterward. Steam's Deck interface and owned library rendered; two debug Superflight launches and Quit exits returned 0 with the same Steam process. The game retained its explicit ARM64 Proton tool/D3D11 arguments; native overlay injection was absent from its mappings. Three minified release launches rendered and Quit returned 0 with the same primary Steam process; the first exercised steering, flight, collision and retry. Home/resume preserved Steam, and force-stopping the app left no UID processes behind.

A first minified release sample on the same S24 and animated 1280×720 Superflight menu:

| Metric | Ubuntu baseline | Arch snapshot |
| --- | --- | --- |
| Aggregate UID PSS |2335.8 MiB |2281.1 MiB |
| Median CPU, percent of one core |267.6% |309.4% |
| Android SurfaceView presentation |34.32 FPS |36.26 FPS |

Arch presented 1609 frames over 44.37 sec; intervals included 677 at 16 ms, 772 at 33 ms, 156 at 50 ms and 4 at 66 ms. CPU used three 5 sec samples, excluding the first `top` sample. These are single samples of a varying generated menu scene, not a controlled engine-FPS or sustained-gameplay comparison. They do not establish that Arch is faster. Broader gameplay, audio, full controls and final performance refinement remain unfinished.

The final combined device suite passed all 12 snapshot, display, Steam, Wine and lifecycle checks (158.019 seconds), including interrupted replacement recovery and cleanup of a read-only previous runtime cache.

The published `androidsteam-runtime-20261004-1` bundle passed the default HTTPS fresh-install check (83.793 seconds) and replacement of the actual Ubuntu root (99.337 seconds), including download cancellation/retry, retained home sentinel, repeated Linux starts and removal of archive/staging/previous-root files. The runtime utility check uses Arch’s `/usr/lib/os-release`; its old Ubuntu path was corrected after installation itself succeeded.

After the HTTPS migration, normal Start Steam replaced the actual old graphics/session bundles with the pinned driver pair and small Android adapters. The saved account/library returned without sign-in. Superflight restarted with the original Proton tool and exact arguments, rendered flight/steering and collision, and the saved high score remained visible. Android’s `input keyevent --duration 150` reliably selected Quit and its confirmation without long-press repeat.

The post-migration Superflight wrapper exited 0 at 20:18:06 UTC and Steam remained alive.
