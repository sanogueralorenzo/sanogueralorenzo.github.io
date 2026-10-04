# Third-party components

Android Deck source is GPL-3.0; see [LICENSE](LICENSE). Steam and games are installed separately and are governed by their own licenses.

| Component | Source and license |
| --- | --- |
| PRoot | [termux/proot, 4dba3afbf3a63af89b4d9c1a59bf2bda10f4d10f](https://github.com/termux/proot/tree/4dba3afbf3a63af89b4d9c1a59bf2bda10f4d10f), GPL-2.0-or-later. Copyright STMicroelectronics and contributors; full notices in `licenses/PROOT-COPYING`. Built unmodified from the pinned, checksum-verified archive. |
| talloc | [Samba talloc 2.4.3](https://www.samba.org/ftp/talloc/talloc-2.4.3.tar.gz), LGPL-3.0-or-later, statically linked into PRoot. Its complete corresponding source is the pinned archive in `native/proot/source.env`. |
| Native build configuration | `native/proot/build.sh`, `source.env`, and `talloc-config.h` adapted from [DroidDeck at 255c64551ec7d5a810da622d918eb88ffdccb231](https://github.com/Droid-Deck/DroidDeck/tree/255c64551ec7d5a810da622d918eb88ffdccb231/tools/proot), GPL-3.0. No downstream PRoot patches included. |
| Ubuntu runtime | [Ubuntu Minimal 24.04 ARM64, release 20261001](https://cloud-images.ubuntu.com/minimal/releases/noble/release-20261001/), downloaded separately. Component copyrights and licenses remain in `/usr/share/doc` inside the installed runtime; no Valve software is included. |
| Commons Compress 1.28.0, Commons IO, Commons Lang, Kotlin, AndroidX test libraries, Gradle wrapper | Apache-2.0. Original notices are retained in dependency archives and wrapper source. |
| XZ for Java 1.12 | [tukaani-project/xz-java](https://github.com/tukaani-project/xz-java), BSD-0-Clause. |

`./gradlew :app:assembleDebug` downloads verified PRoot/talloc sources and builds both from source with the NDK. The source pins, build scripts, app source, and license texts accompany the project; no opaque native prebuilts are checked in. The same source scripts permit rebuilding and modifying the linked LGPL component.
