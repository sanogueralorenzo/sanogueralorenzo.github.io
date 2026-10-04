# Third-party components

Android Deck source is GPL-3.0; see [LICENSE](LICENSE). Steam and games are installed separately and are governed by their own licenses.

| Component | Source and license |
| --- | --- |
| PRoot | [termux/proot, 4dba3afbf3a63af89b4d9c1a59bf2bda10f4d10f](https://github.com/termux/proot/tree/4dba3afbf3a63af89b4d9c1a59bf2bda10f4d10f), GPL-2.0-or-later. Copyright STMicroelectronics and contributors; full notices in `licenses/PROOT-COPYING`. Built from the pinned, checksum-verified archive plus `native/proot/session-cleanup.patch`: clean shutdown on Android's SIGTERM and Linux `PTRACE_O_EXITKILL` for tracer death. |
| talloc | [Samba talloc 2.4.3](https://www.samba.org/ftp/talloc/talloc-2.4.3.tar.gz), LGPL-3.0-or-later, statically linked into PRoot. Its complete corresponding source is the pinned archive in `native/proot/source.env`. |
| Native build configuration | `native/proot/build.sh`, `source.env`, and `talloc-config.h` adapted from [DroidDeck at 255c64551ec7d5a810da622d918eb88ffdccb231](https://github.com/Droid-Deck/DroidDeck/tree/255c64551ec7d5a810da622d918eb88ffdccb231/tools/proot), GPL-3.0. No downstream execution interceptors included. |
| Ubuntu runtime | [Ubuntu Minimal 24.04 ARM64, release 20261001](https://cloud-images.ubuntu.com/minimal/releases/noble/release-20261001/), downloaded separately. Component copyrights and licenses remain in `/usr/share/doc` inside the installed runtime; no Valve software is included. |
| Wayland 1.24.0 | [Upstream release](https://gitlab.freedesktop.org/wayland/wayland/-/releases/1.24.0), MIT; `licenses/WAYLAND-COPYING`. Built from the checksum-verified source; the application implements its Android presentation and shell adapter separately. |
| libffi 3.4.6 | [Upstream release](https://github.com/libffi/libffi/releases/tag/v3.4.6), MIT; `licenses/LIBFFI-LICENSE`. Statically linked into the Wayland protocol engine. |
| xdg-shell protocol | [wayland-protocols 1.45](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/tree/1.45/stable/xdg-shell), checksum-verified XML downloaded during the build. MIT notices retained in `licenses/XDG-SHELL-COPYING` and generated code. |
| Debug Linux client build | Ubuntu GNU libc 2.39-0ubuntu8.9 development/runtime packages, checksum-pinned in `native/display/probe.sh`, are used only as a cross-build sysroot. The debug test executable links to the separately installed runtime's GNU libc; these packages are not bundled in the APK. |
| Commons Compress 1.28.0, Commons IO, Commons Lang, Kotlin, AndroidX test libraries, Gradle wrapper | Apache-2.0. Original notices are retained in dependency archives and wrapper source. |
| XZ for Java 1.12 | [tukaani-project/xz-java](https://github.com/tukaani-project/xz-java), BSD-0-Clause. |

Gradle downloads verified PRoot, talloc, Wayland, and libffi sources and builds them with the NDK. The Wayland scanner also needs a host C compiler and Expat development headers. The source pins, build scripts, app source, and license texts accompany the project; no opaque native prebuilts are checked in. The same source scripts permit rebuilding and modifying the linked LGPL component. Debug builds additionally compile the Linux display test client from source; it is absent from release APKs.
