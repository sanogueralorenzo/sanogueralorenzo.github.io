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

- Native Android project and one-action home screen are implemented. The APK bundles a checksum-verified 194-package ARM64 Linux foundation: 217465328 archive bytes, 916415264 regular-file bytes (about 975 MiB on-device). User home is separate; preparation has cancellation, progress, staged replacement and recovery. The normal desktop launch flow is still unconnected; no Adreno prerequisite remains.
- Android 16 ARM64 `mobile` emulator is running as emulator-5554. JDK 21, SDK 36, NDK 29.0.14206865 and CMake 3.22.1 build successfully; focused lint passes. NDK 29 supplies the C++23 concepts support required by the locked GCC 16/hyprutils headers.
- Rootless software graphics now work: the Amarchy DRM allocator supplies shared-memory buffers to Mesa's existing kms_swrast/LLVMpipe renderer. A real GLES 3.2 frame is exported and checked. The modern desktop host presents these buffers with seat v9, compositor v6 and xdg-shell v6. Its last-frame cache restores a static desktop to a recreated Android surface. Android Steam source is unchanged; the temporary Weston runtime/check and sealed-keymap compatibility adapter have been removed.
- Aquamarine 0.15.1 is rebuilt from checksum-pinned source, with package/source headers confirmed identical. The patch flushes output creation, registers ready outputs and prevents a frame commit before the configure acknowledgement. The patch preserves class layout/ABI. Build-only scanner 0.4.5, pugixml 1.15, GCC headers, systemd headers and hwdata are pinned separately and remain outside the runtime.
- Four emulator integration checks pass (340.303 s, including runtime replacement): exported Mesa frame; real Hyprland/Foot terminal with more than 300000 verified background pixels, Android key events reaching bash, and visible surface recreation; ARM64 shell/Hyprland loading and preserved home; cancelled replacement/interrupted-swap recovery. Actual terminal screenshots were visually inspected. No PRoot, Hyprland, Foot or session D-Bus processes remain after cleanup. These are correctness checks, not startup/FPS measurements.
- Next: connect the verified software session to the normal one-action app flow with explicit lifetime/recovery and Android keyboard/mouse/touch controls. Incorporate pinned Omarchy configuration, themes, launcher and apps; use valid Lua/current Foot configuration and the official session starter to resolve diagnostic warnings. Add audio and everyday desktop integration as needed, then finish lifecycle, accessibility, polish and distribution validation. Do not equate this diagnostic Hyprland session with a completed Omarchy app.
