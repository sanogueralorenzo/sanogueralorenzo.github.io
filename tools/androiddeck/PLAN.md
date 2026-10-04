# Android Deck delivery plan

## Objective

Deliver a polished, minimal Android 16+ app that installs its Linux runtime, launches Valve's Steam Deck interface, and runs a compatible Windows game locally on one validated ARM64 Adreno device. Follow [AGENTS.md](AGENTS.md) for scope and implementation choices.

## Milestones

Complete these in order. A milestone needs working evidence before it is checked off; do independent work when a hardware or account prerequisite is unavailable.

- [x] **1. App foundation:** reproducible Kotlin Views/XML build, `minSdk = 36`, setup/session screens, installation and launch on the Android 16 emulator. Validate execution requirements before settling on `targetSdk`.
- [x] **2. Runtime execution:** pinned runtime, verified download, safe extraction and retry, persistent user data, and a Linux command running through the selected execution path with captured output and exit status.
- [ ] **3. Device graphics:** identify the real device/GPU, select a matched driver pair, and present a Linux Vulkan test through the native Android surface. Retain only demonstrated compatibility requirements.
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

- **Current milestone:** 3 — device graphics.
- **Implemented:** Kotlin/XML app, pinned build, `minSdk = targetSdk = 36`, packaged Termux PRoot + loader; verified Ubuntu Minimal 24.04 ARM64 (20261001), staged installation, persistent home, cancel/retry and Linux check. Wayland 1.24.0/libffi 3.4.6 Android surface/shell adapter and GNU/Linux client library. Candidate Standard Turnip Android/Linux pair `v26.3.0-20261003-r4` (Mesa `e5f0687`), verified staged installer, pinned Linux dependency bundle, and debug-only guest display/driver-load checks.
- **Environment:** Java 21, SDK 36, NDK 28.2.13676358. Android 16 ARM64 emulator `emulator-5554`; Samsung SM-S921U1 currently absent. User has been asked to reconnect it; emulator work continues independently.
- **Decisions:** packaged PRoot loader works at target 36; no lowered target or execution interceptor. Canonical staged extraction and non-following deletion preserve user data. Reuse upstream Wayland; shared-memory frames are a development check. A small PRoot patch reaps tracees on TERM and enables EXITKILL. The candidate driver needs glibc 2.38 (base supplies 2.39), Wayland 1.24 symbols, and XCB 1.17; actual Linux load tests caught and resolved older Wayland/XCB mismatches. Graphics libraries are a separate private overlay, leaving the pinned base and home intact. No GPU fallback or new desktop mode.
- **Next action:** integrate the Android driver loader (upstream libadrenotools), Linux dma-buf protocol, and Vulkan import/presentation into the native bridge, using the pinned pair and relevant WinNative components without effects/frame generation. Identify the reconnected phone/GPU and validate actual Linux Vulkan output. Connect display/activity lifetime to the existing session owner. Driver loading alone does not complete this milestone.
- **Later prerequisites:** real Adreno device for graphics/gameplay; user-controlled Steam authentication and an available compatible game.
- **Validation:** 8 archive tests and 7 emulator integration tests pass. Runtime download/cancel/retry and home preservation were previously validated. Current tests cover Linux commands, surface pixels, failed-start recovery, four display sessions, live-client shutdown and forced tracer death with observed child cleanup; graphics cancellation/retry, home preservation, verified pair installation and two real glibc ICD load/negotiation runs. Debug app/runtime/graphics remain installed. Release shrinking and lint pass; probes are absent from release APKs. No Steam, GPU rendering, gameplay, or comparative performance claims yet.
