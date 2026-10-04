# Android Deck delivery plan

## Objective

Deliver a polished, minimal Android 16+ app that installs its Linux runtime, launches Valve's Steam Deck interface, and runs a compatible Windows game locally on one validated ARM64 Adreno device. Follow [AGENTS.md](AGENTS.md) for scope and implementation choices.

## Milestones

Complete these in order. A milestone needs working evidence before it is checked off; do independent work when a hardware or account prerequisite is unavailable.

- [ ] **1. App foundation:** reproducible Kotlin Views/XML build, `minSdk = 36`, setup/session screens, installation and launch on the Android 16 emulator. Validate execution requirements before settling on `targetSdk`.
- [ ] **2. Runtime execution:** pinned runtime, verified download, safe extraction and retry, persistent user data, and a Linux command running through the selected execution path with captured output and exit status.
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

- **Current milestone:** 1 — app foundation.
- **Implemented:** project guidance and scope; no app code yet.
- **Environment:** Java 21, Android SDK 36, multiple NDK versions, and cached Gradle distributions are installed. Android 16 / API 36 ARM64 emulator connected as `emulator-5554`. Previously connected Samsung SM-S921U1 also reported Android 16; it is currently absent from ADB.
- **Decisions:** minimal Kotlin Views/XML frontend, one Steam mode, one initial real device; execution approach and target SDK need validation.
- **Next action:** select compatible pinned build-tool versions, create the smallest buildable Android app, and install it on the emulator.
- **Later prerequisites:** reconnect the real Adreno device for graphics/gameplay validation; user-controlled Steam authentication and an available compatible game.
- **Validation:** documentation checks only; no runtime or gameplay claims yet.
