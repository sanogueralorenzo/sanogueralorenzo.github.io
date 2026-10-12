# Third-party code

Amarchy reuses the repository's [Android Steam](../androidsteam/THIRD_PARTY.md) PRoot build and Wayland/Android display implementation. The build consumes those pinned source scripts directly; it does not copy Steam, authentication, Proton, or game-control features.

- PRoot: pinned Termux/DroidDeck-derived build and session-cleanup patch, GPL-3.0; attribution and corresponding-source references are in Android Steam's notice.
- Wayland, protocol definitions, libffi, AdrenoTools and LinkerNSBypass: source pins, licenses and notices are retained from Android Steam. License files ship in the APK.
- Runtime packages: exact versions, URLs, checksums, upstreams and declared licenses are in `runtime/packages.lock.json`, also included in the environment. Package-provided licenses and notices remain in the archive. Arch Linux ARM packaging sources are available from https://github.com/archlinuxarm/PKGBUILDs.
- The Amarchy-owned Linux memory adapter implements the Wayland keymap's private-mapping semantics for immutable, read-only sealed buffers, addressing the reproduced Android/Weston input failure. Source is in `native/desktop_memory.c` (GPL-3.0-only).
- Apache Commons Compress: Apache-2.0. XZ for Java: public domain.

Amarchy is an independent Android adaptation. Desktop integration is under development; this foundation does not yet contain a working Omarchy session.
