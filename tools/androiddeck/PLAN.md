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
- **Implemented:** Kotlin/XML app, `minSdk = targetSdk = 36`, packaged PRoot + loader, verified Ubuntu Minimal 24.04 ARM64 (20261001), staged setup/cancel/retry, persistent home, and Linux execution. Wayland 1.24.0/libffi 3.4.6 Android adapter and GNU/Linux client library. Verified candidate Standard Turnip pair `v26.3.0-20261003-r4` (Mesa `e5f0687`) and pinned Linux libraries. Source-built libadrenotools, native Vulkan surface/copy path, single-plane BGRA dma-buf import/feedback, and explicit synchronization. Debug-only Linux Vulkan client and opt-in device pixel/restart check are prepared; actual GPU rendering remains unvalidated.
- **Environment:** Java 21, SDK 36, NDK 28.2.13676358. Android 16 ARM64 emulator `emulator-5554`; Samsung SM-S921U1 currently absent. User has been asked to reconnect it; emulator work continues independently.
- **Decisions:** packaged PRoot loader works at target 36; no lowered target or execution interceptor. Safe staged extraction preserves the separate home. PRoot TERM/EXITKILL cleanup is patched and verified. Graphics dependencies need glibc 2.38 (base 2.39), Wayland 1.24, and XCB 1.17; a private overlay preserves the base. Reuse upstream Wayland/libadrenotools and relevant WinNative import/feedback patterns. Cache the fixed Android driver once per process because linker namespaces cannot be deleted; require the pinned Turnip identity and sharing capabilities. Explicit acquire descriptors transfer to Vulkan; completed copies permit buffer release. Only required custom-driver hooks are packaged. Shared-memory display is a separate development check; no production GPU fallback, effects, or desktop mode.
- **Next action:** identify the reconnected phone/GPU, install the runtime there, and run `verifyVulkan=true` to validate actual Linux Vulkan pixels, synchronization, reattachment, and restart. If the phone is still unavailable, connect production display/activity lifetime and errors to the existing session owner while keeping the hardware check open. Inspect failures against the small native adapter rather than adding speculative compatibility switches. Driver loading/build success does not complete this milestone.
- **Later prerequisites:** real Adreno device for graphics/gameplay; user-controlled Steam authentication and an available compatible game.
- **Validation:** 8 unit tests and 8 emulator integration tests pass; the ninth integration test (real Vulkan pixels) is explicitly skipped until requested on hardware. Checks cover Linux execution, actual shared-memory pixels, four display sessions, live-client/forced-tracer cleanup, candidate pair installation/loading, and three unsupported-GPU starts followed by a clean development-display restart. Earlier download/cancel/retry and home preservation checks passed. Debug app/runtime/graphics remain installed; no stale guest processes. Release shrinking/lint pass, notices are packaged, and probes/unused hooks are excluded from release. No Steam, hardware rendering, gameplay, or comparative performance claims yet.
