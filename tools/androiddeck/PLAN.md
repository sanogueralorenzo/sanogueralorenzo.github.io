# Android Deck delivery plan

## Objective

Deliver a polished, minimal Android 16+ app that installs its Linux runtime, launches Valve's Steam Deck interface, and runs a compatible Windows game locally on one validated ARM64 Adreno device. Follow [AGENTS.md](AGENTS.md) for scope and implementation choices.

## Milestones

Complete these in order. A milestone needs working evidence before it is checked off; do independent work when a hardware or account prerequisite is unavailable.

- [x] **1. App foundation:** reproducible Kotlin Views/XML build, `minSdk = 36`, setup/session screens, installation and launch on the Android 16 emulator. Validate execution requirements before settling on `targetSdk`.
- [x] **2. Runtime execution:** pinned runtime, verified download, safe extraction and retry, persistent user data, and a Linux command running through the selected execution path with captured output and exit status.
- [x] **3. Device graphics:** identify the real device/GPU, select a matched driver pair, and present a Linux Vulkan test through the native Android surface. Retain only demonstrated compatibility requirements.
- [ ] **4. Steam session:** install Valve's client, launch its Deck interface, support keyboard/pointer input, and verify sign-in and the library. Let the user perform account authentication.
- [ ] **5. Playable game:** run an available, compatible Windows game through Proton with working graphics, audio, controller/touch input, and repeatable stop/relaunch. No game purchases are assumed.
- [ ] **6. Polish and delivery:** finish setup guidance and actionable errors, verify interruption/failure cleanup and user-data preservation, address measured bottlenecks, and deliver a release APK with concise setup instructions and required licenses.

## Completion criteria

- A fresh installation can reach Steam through the documented setup on the validated device without root.
- A compatible game runs locally with usable audio and input; stopping and relaunching leave no stale session processes.
- Download/install failures and session interruptions recover predictably without losing Steam user data.
- Release builds have focused validation and recorded startup, memory, idle CPU, and relevant frame/input measurements. Performance claims require comparable evidence.
- The UI has coherent loading, ready, running, and error states; temporary scaffolding and unused code/dependencies are removed.
- The release APK, current setup documentation, licenses, and committed implementation are available; changes are pushed to `main`.

## Resume state

Update this section in place; keep it concise rather than appending a work log.

- **Current milestone:** 4 — Steam session.
- **Implemented:** Kotlin/XML app, `minSdk = targetSdk = 36`, packaged PRoot + loader, verified Ubuntu Minimal 24.04 ARM64 (20261001), staged setup/cancel/retry, persistent home, and Linux execution. Wayland 1.24.0/libffi 3.4.6 Android adapter and GNU/Linux client library; matched Standard Turnip pair `v26.3.0-20261003-r4` (Mesa `e5f0687`) with verified private Linux libraries. Native Vulkan surface, single-plane BGRA dma-buf import/feedback, explicit and implicit producer-fence waits. Actual Linux Vulkan pixels, surface reattachment, shutdown, and restart pass on the S24. The display is not yet connected to the app's session UI.
- **Environment:** Java 21, SDK 36, NDK 28.2.13676358. USB-connected Samsung S24 SM-S921U1, Android 16/API 36, ARM64, SM8650/Adreno 750; ADB serial `RFCWC0YTYGW`. Use this phone for device tests per the user. Runtime and graphics remain installed.
- **Decisions:** APK-packaged PRoot loader works at target 36; no execution interceptor or lowered target. Staged extraction preserves the separate home; TERM/EXITKILL cleanup is verified. Graphics overlay needs glibc 2.38 (base 2.39), Wayland 1.24, and XCB 1.17. Fixed Android driver is cached per process; require pinned Turnip identity and sharing capabilities. Explicit acquire descriptors transfer to Vulkan. For implicit clients, export the dma-buf writer fence and import it into the same GPU wait; foreign image ownership alone allowed stale frames. Completed copies permit buffer release. Shared-memory display remains a separate debug check; no GPU fallback or desktop mode.
- **Next action:** connect display/activity lifetime and errors to one session owner, then install the native ARM64 stable Steam Deck client and the required Gamescope/XWayland session components. Inspect only relevant reference code and upstream contracts; do not copy unneeded desktop features or compatibility switches. Steam owns authentication and its library.
- **Research ready:** authoritative stable manifest `https://client-update.fastly.steamstatic.com/steam_client_steamdeck_stable_linuxarm64` has ARM64 client archives with per-file sizes and SHA-256 hashes. Reference sessions launch Steam's `steamrtarm64/steam` through Gamescope's Wayland backend with Deck mode. Verify dependencies and behavior on our phone before adopting workarounds.
- **Later prerequisites:** user-controlled Steam authentication and an available compatible game.
- **Validation:** on the S24, fresh runtime install/cancel/retry and real Linux execution pass; the broader integration run passes (two prerequisite-inapplicable tests skipped). Twenty consecutive Vulkan checks exercise forty display sessions, three frames each, nine final-frame pixel samples, reattachment, and cleanup. Missing implicit producer synchronization reproduced as a persistent stale red frame before the fix. Release build/lint pass; release excludes probes and unused hooks and includes notices. Prior unit tests pass. No Steam, gameplay, or comparative performance claims yet.
