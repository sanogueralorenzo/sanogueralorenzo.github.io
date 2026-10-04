# Android Deck delivery plan

## Objective

Deliver a polished, minimal Android 16+ app that installs its Linux runtime, launches Valve's Steam Deck interface, and runs a compatible Windows game locally on one validated ARM64 Adreno device. Follow [AGENTS.md](AGENTS.md) for scope and implementation choices.

## Milestones

Complete these in order. A milestone needs working evidence before it is checked off; do independent work when a hardware or account prerequisite is unavailable.

- [x] **1. App foundation:** reproducible Kotlin Views/XML build, `minSdk = 36`, setup/session screens, installation and launch on the Android 16 emulator. Validate execution requirements before settling on `targetSdk`.
- [x] **2. Runtime execution:** pinned runtime, verified download, safe extraction and retry, persistent user data, and a Linux command running through the selected execution path with captured output and exit status.
- [x] **3. Device graphics:** identify the real device/GPU, select a matched driver pair, and present a Linux Vulkan test through the native Android surface. Retain only demonstrated compatibility requirements.
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

- **Current milestone:** 4 — Steam session.
- **Implemented:** Kotlin/XML app, `minSdk = targetSdk = 36`, packaged PRoot + loader, verified Ubuntu Minimal 26.04 ARM64 (20261002) with the pinned GNU Coreutils provider, staged setup/cancel/retry, persistent home, and Linux execution. Wayland 1.24.0/libffi 3.4.6 Android adapter and GNU/Linux client library; matched Standard Turnip pair `v26.3.0-20261003-r4` (Mesa `e5f0687`) with verified private Linux libraries. Native Vulkan surface, single-plane BGRA dma-buf import/feedback, explicit and implicit producer-fence waits. Actual Linux Vulkan pixels, surface reattachment, shutdown, and restart pass on the S24. The stable native ARM64 Steam client (`1788652215`) installs directly from Valve with component hashes, bounded staged ZIP extraction, Windows-path normalization, safe deferred links, and persistent home. A pinned Gamescope/XWayland bundle and staged session-component installer are implemented; the display and installers are not yet connected to the app's session UI.
- **Environment:** Java 21, SDK 36, NDK 28.2.13676358. USB-connected Samsung S24 SM-S921U1, Android 16/API 36, ARM64, SM8650/Adreno 750; ADB serial `RFCWC0YTYGW`. Use this phone for device tests per the user. Runtime and graphics remain installed.
- **Decisions:** APK-packaged PRoot loader works at target 36; no execution interceptor or lowered target. Staged extraction preserves the separate home; TERM/EXITKILL cleanup is verified. Graphics overlay needs glibc 2.38 (base 2.43), Wayland 1.24, and XCB 1.17. Tar hard links become contained symbolic aliases instead of duplicated files. Resolute's Rust multicall utilities reject those aliases, so the supported GNU provider replaces them; redundant Rust binaries/aliases are removed. Fixed Android driver is cached per process; require pinned Turnip identity and sharing capabilities. Explicit acquire descriptors transfer to Vulkan. For implicit clients, export the dma-buf writer fence and import it into the same GPU wait; foreign image ownership alone allowed stale frames. Completed copies permit buffer release. Shared-memory display remains a separate debug check; no GPU fallback or desktop mode.
- **Next action:** implement honest presentation-time feedback from Android presentation completion. Gamescope checks `wp_presentation` in `main.cpp` before SDL startup and forces X11 without it; the S24 probe therefore exits before rendering. Inspect the Android loader's actual timing capabilities and the protocol contract; do not report submitted GPU work as displayed or advertise fabricated timing. Then validate Gamescope's fixed SDL/Wayland path, resolve demonstrated requirements, and connect display/activity lifetime to one session owner. Before Steam network startup, verify Linux DNS (`etc/resolv.conf` is absent). Steam owns authentication and its library.
- **Research ready:** the distro bundle uses Gamescope 3.16.20+ds-1 and XWayland 24.1.10. `native/session/packages.tsv` pins 124 binaries, resolved against the installed root's actual dpkg status; the cloud image manifest included absent libraries. `sources.tsv` pins their 87 corresponding source packages. All Ubuntu bundles share verified cached download/extraction, and exclude macOS metadata that broke Gamescope's Lua loading. The current session component version is 3; X11's directory-self alias extracts correctly. Relevant upstream Gamescope, SDL, Mesa, presentation protocol, and AOSP loader sources are cached under `/tmp/androiddeck-*`. AOSP's `vulkan/libvulkan/swapchain.cpp` implements `VK_GOOGLE_display_timing` with actual native-window timestamps; inspect whether our Adrenotools-loaded Android driver exposes that loader path before choosing the feedback implementation. Gamescope's SDL backend uses one Vulkan swapchain; its native Wayland backend requires eight planes and more protocols. Steam's stable package list is in the app assets with Valve's per-file hashes.
- **Later prerequisites:** user has a Steam account with games. Pause the goal when the sign-in screen is ready for their authentication; resume after login to select a compatible owned game.
- **Validation:** fresh Resolute/GNU installation with download cancellation/retry and command aliases passes on the S24 (68.105 seconds); installed runtime is 469 MiB. Steam's main executable hash is unchanged across base replacement. The broader real-device run passes nine applicable tests (one unsupported-GPU check skipped), including Linux commands, shared-memory pixels/cleanup, graphics loading, Vulkan readback/reattachment/restart, and installed Steam links/idempotence. Native producer-fence handling previously passed twenty consecutive Vulkan checks. Twelve unit tests, release build, and lint pass. No Steam interface, gameplay, or comparative performance claims yet.
