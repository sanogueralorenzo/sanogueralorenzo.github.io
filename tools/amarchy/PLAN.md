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

- Native Android project and one-action home screen are implemented. The APK bundles a checksum-verified 223-package ARM64 Linux foundation (~234 MiB compressed, ~1.1 GiB installed). User home is separate; preparation has cancellation, progress, staged replacement and recovery. Desktop startup is explicitly unavailable until graphics integration works.
- Android 16 ARM64 `mobile` emulator is running as emulator-5554; JDK 21, SDK 36 and NDK 28.2.13676358 are available. Debug APK/test builds and focused lint pass. The home screen was visually inspected in the emulator.
- Three emulator integration checks pass on the final foundation build (52.609 s): real ARM64 shell and Hyprland 0.56.2/matched library loading with persistent home; cancelled replacement and interrupted-swap recovery; a real Foot terminal rendered by Weston through the shared-memory Android bridge, keyboard input reaching bash, surface detach/reattach and clean shutdown. No Linux processes remain afterward. Weston is a diagnostic compositor, not the delivered Omarchy desktop.
- Android rejects Weston's shared mapping of the sealed keyboard map. The Amarchy-only Linux adapter maps immutable read-only sealed buffers privately; mutable display/audio mappings remain shared. This fixes the demonstrated end-to-end input failure. Android Steam source is unchanged.
- Current Hyprland/Aquamarine require DRM/GBM and DMA-BUF for nested rendering. The emulator has no `/dev/dri` or Adreno device; its kernel disables CONFIG_DRM_VIRTIO_GPU. A CPU renderer alone is insufficient. Do not assert desktop feasibility until an actual graphics approach is demonstrated.
- Next: establish a real Hyprland graphics path. Investigate an Android-compatible GBM/DRM allocation path or a working emulator GPU configuration, then incorporate pinned Omarchy desktop configuration and applications. Never substitute the Weston diagnostic session for completion or claim loaded Hyprland is a rendered desktop.
