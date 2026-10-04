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

## Audio foundation

A standard Linux PulseAudio 17 server supplies the UNIX protocol and pipe sink; Kotlin feeds its fixed 48 kHz stereo 16-bit PCM to one Android AudioTrack. The source-pinned runtime keeps those modules, their protocol library and actual shared-library dependencies. Unused system-daemon, realtime-service and optional DSP modules are excluded. The corrected 245-package candidate is 162610928 bytes (SHA-256 `68cb9c890584af3202a8b6cf0903efdc7c69467b77eae29d10d2a264a43132c3`); two independent builds match. The final snapshot passed replacement, cancellation and interrupted-swap recovery in 139.45 seconds. Publication and default HTTPS replacement are pending.

The S24 consumed real Linux-generated PCM twice, then passed a 9.653-second repeated playback/visibility/restart check. Neither run had an underrun during the checked steady tone; counters at the end also include startup/end-of-stream behavior. Visibility changes mute output while PCM keeps advancing, avoiding stale sound on return.

The first real Superflight stream was active with about 300–311 ms reported sink latency and 21.5 ms client latency. Android initially allocated 4800 frames (100 ms). Configuring the FIFO to 4096 bytes before Pulse reads its capacity and the Android playback limit to 960 frames reduced those queue bounds to 21.3 ms and 20 ms. These buffer durations are not an acoustic end-to-end latency measurement. Tuned Superflight reported 10–20 ms sink latency and 20–30 ms client latency during actual flight/steering. Home/resume retained Steam31458, Pulse31317 and game32289; the app restored its own track gain to 1.0. Media volume was zero, so the device checks establish PCM delivery and gain restoration, not an acoustic speaker test. On normal session stop, Android consumed 17986680 frames from 71946720 bytes, with 4177393 nonzero samples and three total underruns including startup/stream boundaries. No Linux child remained. Final default-download validation remains pending.

The combined PCM, Gamescope and Steam lifecycle checks passed all four tests in 26.022 seconds on the final bundle. The lifecycle check deliberately terminates PulseAudio, verifies session failure cleanup, starts Steam again and repeats Home/resume before normal stop. It exposed a stale surfaceDestroyed callback from the departing activity detaching the newly attached display. Surface ownership now rejects that callback; diagnostic tracing was removed. The audio test clears previous task UI before launch to avoid resuming an unrelated old session while checking standalone audio.

The minified release preserved the saved account/library and ran Superflight through Steam with the saved configuration. Flight, steering, collision and Quit worked; Steam8863 remained alive after game9835 exited. Home/resume retained both processes and Pulse8703; Android track gains changed1→0→1 while PCM continued advancing. The expanded notification Stop Steam action closed the session and left only the Android process. Release totals:37335960 bytes,9333990 played frames,6376512 nonzero samples,960-frame buffer and6 total underruns, including startup and stream boundaries. Phone media volume remained0. Animated-menu measurements were2218.5MiB aggregate UID PSS and CPU samples305.8/295.4/300.0% of one core (median300.0%). Generated scenery varies, so these samples do not establish a performance improvement. Evidence: `/tmp/androidsteam-superflight-audio-release-measurement.json`.
