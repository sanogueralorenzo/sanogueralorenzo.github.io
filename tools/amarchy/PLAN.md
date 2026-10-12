# Amarchy

## Objective

Create a polished Android app hosting an Android-adapted ARM64 Omarchy desktop, with the fewest practical setup steps and a smooth everyday experience. Verify behavior in the emulator where appropriate, follow repository guidance, and commit/push completed work to main.

## Completion criteria

- One primary action prepares a verified environment and enters the real desktop; later opens reuse setup/session state.
- A polished, accessible frontend handles progress, cancellation, retry, storage/network failures, keyboard access, and session controls.
- Real Omarchy/Hyprland apps render and accept input. Background/resume, stop/relaunch, process cleanup, and persistent home data work.
- Runtime inputs and upstream adaptations are pinned, reproducible, and attributed.
- Focused checks and documented emulator/device evidence pass; completed changes are committed and pushed to main.

## Milestones

1. Establish the Android project, installation/session ownership, and polished one-action frontend.
2. Prove ARM64 Linux execution and display transport on Android 16 in the emulator.
3. Assemble an Omarchy runtime and establish a working Hyprland graphics path; validate real desktop applications and input.
4. Finish the everyday desktop experience, lifecycle/recovery checks, brief setup documentation, and distribution.

## Resume state

- The normal one-action flow now opens a real Omarchy/Hyprland session. Android owns preparation, surface attachment, foreground lifetime, cancellation, failure recovery and process cleanup. Home retains the session; Close desktop stops it. The session runs as guest UID 1000 through the official session starter. Projects/settings live in a separate persistent home.
- The checksum-verified runtime contains 482 pinned ARM64 packages and Omarchy revision `9480d1b6a98156314dbabe6bfef08f39f8b9cd07`. Its bootstrap, helpers, look/feel and tiling defaults load with Android overrides. Terminal, Nautilus, Neovim and Chromium render. Touch/mouse/physical keys, Android IME Unicode typing, clipboard paste and shortcut controls work. Full-OS boot/hardware services are excluded.
- Deterministic gzip replaces Java XZ extraction. The asset is named `environment.tar.gzip` to prevent Android's asset merger from transparently expanding `.gz`. Archive: 946877315 bytes, SHA256 `a8b315f98bc57581eafc137c4f8fa9cf8e3bcfb4999f27f9fb42319d81e082ef`; regular files: 2609773598 bytes. On the dedicated AVD, extraction took 50.5 s and total preparation 74.6 s; observed warm desktop readiness was 1.36–1.51 s. These are individual runs, not performance guarantees.
- Dedicated Android 16 ARM64 Pixel 9 AVD `amarchy` is emulator-5556 (16 GB data, 4 GB RAM, four cores). Existing `mobile` emulator-5554 data is preserved. JDK 21, SDK 36, NDK 29.0.14206865 and CMake 3.22.1 build successfully; focused lint passes. NDK 29 provides the required C++23 header support.
- Rootless Mesa kms_swrast/LLVMpipe renders through Amarchy's shared-memory DRM allocator and modern Wayland host. Aquamarine 0.15.1 has an ABI-preserving startup/configure patch and explicit `glFinish` before software-buffer presentation, fixing partial frames without kernel fences. Long private Hyprland control sockets use a path-keyed abstract namespace under `/run/user/1000/hypr/`. The host retains the last frame across Android surface replacement. Android Steam source is unchanged.
- Six combined emulator tests passed in 84.726 s: GLES frame/export, real Hyprland/Foot pixels and surface restoration, normal one-action launch/Unicode input/background-resume/stop-relaunch, Terminal/Files/Editor/Browser clients, ARM64 runtime/persistent home, and cancelled/interrupted installation recovery. App screenshots were visually inspected. No PRoot, Hyprland, Foot, Nautilus, Chromium, Neovim or session D-Bus processes remained after cleanup.
- Next: polish phone viewport/keyboard readability and window navigation; finish audio, coherent dark GTK appearance, command-failure feedback, network-change behavior and browser connectivity. Complete frontend accessibility/error checks, runtime reproducibility/license audit (also embed Omarchy source lock), and release/minified APK acceptance. Fixed 1280×720 letterboxing currently shrinks excessively with the phone keyboard; audio is not implemented. Keep this goal active until the everyday experience and distribution criteria pass.
