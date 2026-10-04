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
- **Implemented:** standalone Kotlin/XML app, pinned Gradle/AGP/Kotlin build, `minSdk = targetSdk = 36`, packaged unmodified Termux PRoot + loader built from verified sources. Pinned Ubuntu Minimal 24.04 ARM64 (20261001), verified download, bounded staged extraction, separate persistent home, cancel/retry and Linux startup check.
- **Environment:** Java 21, SDK 36, NDK 28.2.13676358. Android 16 ARM64 emulator `emulator-5554`; Samsung SM-S921U1 currently absent. User has been asked to reconnect it; emulator work continues independently.
- **Decisions:** packaged PRoot loader runs both writable Bionic and real glibc executables at target 36, so no lowered target or exec interceptor. Base Ubuntu runtime instead of a complete downstream gaming image. Archive hard links become copies because Android storage forbids linking; canonical paths prevent alias errors; cleanup never follows symbolic links.
- **Next action:** integrate the smallest established Wayland/native-surface bridge and one pinned matched Adreno driver pair. Compare upstream WinNative bridge components with the expanded reference compositor; omit frame-generation/effects/desktop code. Validate Linux Vulkan output on the phone when available.
- **Later prerequisites:** real Adreno device for graphics/gameplay; user-controlled Steam authentication and an available compatible game.
- **Validation:** 8 archive safety tests pass; 5 emulator tests passed, including an interrupted real download followed by successful retry, user-home preservation, staged-file cleanup, two glibc/Linux runs and cancelled-command relaunch at target 36. The debug app and runtime are left installed on the emulator. Release shrinking and lint pass. No Steam, GPU, gameplay, or comparative performance claims yet.
