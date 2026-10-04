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
- **Implemented:** standalone Kotlin/XML app, pinned build, `minSdk = targetSdk = 36`, packaged Termux PRoot + loader; pinned Ubuntu Minimal 24.04 ARM64 (20261001), verified staged installation, persistent home, cancel/retry and Linux startup check. Upstream Wayland 1.24.0/libffi 3.4.6 with a small native Android surface/shell adapter; debug-only GNU/Linux client sends shared-memory frames through the actual guest runtime.
- **Environment:** Java 21, SDK 36, NDK 28.2.13676358. Android 16 ARM64 emulator `emulator-5554`; Samsung SM-S921U1 currently absent. User has been asked to reconnect it; emulator work continues independently.
- **Decisions:** packaged PRoot loader works at target 36; no lowered target or execution interceptor. Archive hard links become copies; canonical paths and non-following deletion protect extraction. Reuse upstream Wayland protocol handling rather than adopting the expanded compositor or a separate Xorg app. Shared-memory presentation is a development check, not the GPU path. Live-client tests demonstrated that upstream PRoot ignores Android's SIGTERM; a small source patch now reaps tracees on TERM and enables kernel EXITKILL for unexpected tracer death.
- **Next action:** identify the connected phone/GPU and pin one matched Android/Linux Turnip driver pair. Add Linux dma-buf transport and Vulkan import/presentation to the native bridge, using relevant upstream WinNative/driver code and excluding effects/frame generation. Validate actual Linux Vulkan output on the phone; complete the remaining protocol and activity/session integration required by that path.
- **Later prerequisites:** real Adreno device for graphics/gameplay; user-controlled Steam authentication and an available compatible game.
- **Validation:** 8 archive tests and 6 emulator integration tests pass. Runtime download/cancel/retry and user-home preservation were validated during foundation work. Current tests cover Linux checks, actual display pixels, failed-start recovery, four display sessions, shutdown with a live client, and forced tracer death; observed Linux child PIDs disappear after both shutdown paths. Debug app/runtime remain installed. Release shrinking and lint pass; Linux/display probes are absent from the release APK. No Steam, GPU, gameplay, or comparative performance claims yet.
