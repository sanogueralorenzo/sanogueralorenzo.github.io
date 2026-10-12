# Third-party code

Amarchy reuses the repository's [Android Steam](../androidsteam/THIRD_PARTY.md) pinned PRoot build and adapts its Wayland/Android display and input implementation for a nested desktop. The software bridge and Linux memory allocator are Amarchy-owned; Steam, authentication, Proton and game-control features are excluded.

- PRoot: pinned Termux/DroidDeck-derived build and session-cleanup patch, GPL-3.0; attribution and corresponding-source references are in Android Steam's notice.
- Wayland 1.24.0, Wayland protocols 1.45, libffi 3.4.6 and the self-contained US keymap: pins and notices are retained from Android Steam. The desktop bridge uses modern seat/compositor/xdg-shell protocols and presents memory-backed Mesa frames. Amarchy does not load an Adreno driver.
- Runtime packages: exact versions, URLs, checksums, upstreams and declared licenses are in `runtime/packages.lock.json`, also included in the environment. Package-provided licenses and notices remain in the archive. Arch Linux ARM packaging sources are available from https://github.com/archlinuxarm/PKGBUILDs.
- The Amarchy-owned software DRM allocator shares memory-backed buffers with Mesa's existing kms_swrast/LLVMpipe renderer. Source is in `native/software_drm.c` (GPL-3.0-only). It uses neither root nor hardware GPU access.
- Aquamarine 0.15.1 (BSD-3-Clause): rebuilt from the checksum-pinned source with an ABI-preserving nested-Wayland startup patch. It flushes output creation, publishes ready outputs and queues configure acknowledgements before rendering. The original package's headers match the source headers. Build-only hyprwayland-scanner 0.4.5, pugixml 1.15 and GCC 16.1.1 headers are pinned in `native/aquamarine/sources.lock.json`. Their source archives are directly linked by that lock; the patched backend is reproducible with NDK 29.
- Apache Commons Compress: Apache-2.0. XZ for Java: public domain.

Amarchy is an independent Android adaptation. Hyprland software rendering is verified in the emulator; Omarchy configuration, applications and the normal desktop launch flow remain under development.
