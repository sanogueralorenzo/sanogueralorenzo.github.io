# Arch runtime minimization

S24 SM-S921U1, Android 16, Adreno 750. Accounts, games, saves and profiles stay in the separate home; runtime candidates use staged replacement with recovery. Steam and ARM64 Proton retain their own updates.

## First content batch (2026-10-05)

The official Arch ARM core/extra database hashes still match the reviewed 245-package lock. Package payload downloads for rebuilding total 215003980 bytes; users download the assembled snapshot instead. Required certificates, fonts, graphics, audio, gconv encodings, GTK loaders, notices and provenance remain.

Remove manuals while retaining license/copyright/notice/authorship files; remove locale-generation sources/tools because the session uses glibc's built-in C.UTF-8; remove Mesa's neural-inference API, which the Zink/Turnip path does not use. This batch keeps the package closure unchanged.

| Metric | Original snapshot | Candidate |
| --- | ---: | ---: |
| Base archive bytes | 162610928 | 153760944 |
| Android runtime disk usage, KiB | 817661 | 761463 |
| Installed regular-file bytes, host audit | 794185726 | 742683666 |
| Extraction/cache preparation, ms | 72672 | 67518 |
| Pinned base + drivers + Steam bootstrap downloads, bytes | 526068606 | 517218622 |

Download totals exclude the APK, Steam's subsequent updates, Proton and games. The current Steam bootstrap contributes 357602688 bytes; the matched driver archives contribute 5854990 bytes. Preparation timing is one device sample per configuration, excluding network transfer; it does not establish a repeatable setup/runtime speed improvement.

Two independent builds produce SHA-256 `59bae3f21e0e31375589e02deec5f813398342431b018f16102a3522d87745ab`. The candidate passes isolated extraction, replacement, cancellation, truncated archive failure and interrupted-swap recovery (134.835 seconds), retaining the home sentinel. Ten S24 dependency/font/DNS/audio/rendering/lifecycle checks pass against the activated candidate (31.376 seconds). The source-matching minified release retains the account, five installed games, saved Superflight score and Arrow profile. Superflight renders flight, touch steering, collision and Home/resume; two native Play launches and Quit exits retain the same Steam process. Notification Stop removes all Linux processes. No new snapshot is published yet. The original device runtime remains in `runtime-goal-baseline` for recovery.

## Standalone tools and Zink-only Mesa

The second batch removes 14 SQLite inspection/synchronization, conversion and diagnostic executables listed in `native/runtime/unused-tools.txt`; their libraries and dynamically loaded resources remain. It passes replacement/recovery (133.442 s), ten focused device checks (32.635 s), release Superflight gameplay, exit and warm relaunch with the same Steam process, and complete notification shutdown.

The third batch builds upstream Mesa 26.2.3 for Zink only, using the existing matched Turnip Vulkan driver. Source checksums, NDK/tool versions and build-only GCC/protocol packages are reviewed in `native/runtime/mesa`. LLVM, sensor and SPIR-V diagnostic dependencies disappear from the resulting ELF dependencies; the other upstream Mesa dependencies remain. This reduces the closure from 245 to 242 packages. The main Gallium library shrinks from 53602840 to 19068080 bytes. No development inputs are shipped.

| Metric | Original | Tools removed | Zink-only candidate |
| --- | ---: | ---: | ---: |
| Base archive bytes | 162610928 | 146292168 | 99009976 |
| Android runtime disk usage, KiB | 817661 | 732947 | 522273 |
| Installed regular-file bytes | 794185726 | 713499835 | 498125729 |
| Extraction/cache preparation, ms | 72672 | 66260 | 54473 |
| Base + drivers + Steam bootstrap bytes | 526068606 | 509749846 | 462467654 |

Preparation is one fresh sample each, excluding network transfer. The observed reduction is not a general setup-time guarantee or graphics performance claim. The current installed Steam-managed ARM64 Proton depot adds 497871024 download bytes and 2080051656 installed bytes; Valve may update it independently. The Zink candidate's Arch package downloads for rebuilding total 176103764 bytes, with additional source/compiler inputs used only on the build host.

Two independent final builds produce SHA-256 `5d9571fd3e463a39dc33f052e693f6dc3069508eb5969cde2f7d8908d1115318`. Replacement, cancellation, truncation failure and interrupted-swap recovery pass (109.784 s), and eleven graphics/dependency/audio/lifecycle checks pass (30.289 s). Release Superflight renders saved scores/flight, survives Home/resume and completes Quit/warm Play/Quit with Steam PID 6875 retained. Warm game process appearance was observed 16.0 s after native Play; this is not a usable-menu measurement. Brotato GLES2 resumes its saved run, renders wave-3 gameplay, responds to touch WASD steering and survives Home/resume with Steam 6875/game 12203 retained. Its original Direct touch choice was restored after movement checks. Brotato returns to its main menu with a resumable run, then Quit returns to native details while Steam remains alive. Notification Stop reaps every Linux session process. Earlier device roots remain preserved.

## Release regression sample

Same APK, device, Steam/Proton, drivers, D3D11 1280×720 and Arrow overlay; Superflight's generated animated menu differs between runs. Both samples report light thermal throttling, with skin temperature increasing from about 40.2–40.6°C to 40.2–41.2°C. These samples verify rendering/resource behavior, not a speed or memory improvement.

| Metric | Original snapshot | Candidate |
| --- | ---: | ---: |
| Aggregate UID PSS, MiB | 2280.0 | 2341.9 |
| Median CPU, percent of one core | 332.2 | 298.6 |
| Android SurfaceView presentations/s | 33.960 | 29.218 |
| Observed presented frames | 623 | 541 |

CPU uses three 5-second samples after discarding the first `top` sample. Android presentation rate is not engine FPS. The differing generated scene and thermal state prevent interpreting these differences as an effect of removing unused files.

## Reproduce the audit

Extract the bundle onto a case-sensitive filesystem, then run:

```sh
python3 native/runtime/audit.py /path/to/extracted-root /path/to/package-cache > audit.json
```

The audit uses package metadata/file manifests to attribute retained sizes and show dependency paths. Optional `--steam-files names.txt` compares names from Steam's ARM64 binary/library directories. Name overlap establishes neither ABI compatibility nor safe removal. Never include account/configuration/log files in that input.

The retained ICU, Python, GTK/Glycin, fonts and loaders include dynamic dependencies/resources that Steam or Proton can select at runtime. Overlapping names in Steam's private runtime are insufficient evidence to replace Arch libraries: loader paths, ABI versions and child-process environments must also agree. The Zink build removes the largest demonstrated unnecessary dependency chain; further removals require equivalent real-device validation.
