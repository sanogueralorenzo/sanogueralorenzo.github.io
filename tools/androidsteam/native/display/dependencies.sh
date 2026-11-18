#!/usr/bin/env bash
set -euo pipefail
: "${NDK:?Set NDK to the pinned Android NDK}"
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/source.env"
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
case "$(uname -s)" in
    Darwin) HOST=darwin-x86_64 ;;
    Linux) HOST=linux-x86_64 ;;
    *) printf '%s\n' 'Build host must be macOS or Linux x86_64.' >&2; exit 1 ;;
esac
TOOLS="$NDK/toolchains/llvm/prebuilt/$HOST/bin"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
rm -rf "$OUT/wayland" "$OUT/ffi" "$OUT/ffi-build" "$OUT/ffi-install" "$OUT/generated" "$OUT/adrenotools"
fetch() {
    curl -fsSL --retry 3 "$2" -o "$WORK/archive"
    printf '%s  %s\n' "$3" "$WORK/archive" | shasum -a 256 -c -
    mkdir -p "$OUT/$1"
    tar -xf "$WORK/archive" --strip-components=1 -C "$OUT/$1"
}
fetch wayland "https://gitlab.freedesktop.org/wayland/wayland/-/releases/$WAYLAND_VERSION/downloads/wayland-$WAYLAND_VERSION.tar.xz" "$WAYLAND_SHA256"
fetch ffi "https://github.com/libffi/libffi/releases/download/v$FFI_VERSION/libffi-$FFI_VERSION.tar.gz" "$FFI_SHA256"
fetch adrenotools "https://github.com/bylaws/libadrenotools/archive/$ADRENOTOOLS_COMMIT.tar.gz" "$ADRENOTOOLS_SHA256"
fetch adrenotools/lib/linkernsbypass "https://github.com/bylaws/liblinkernsbypass/archive/$LINKER_COMMIT.tar.gz" "$LINKER_SHA256"
mkdir -p "$OUT/protocols"
curl -fsSL --retry 3 "https://raw.githubusercontent.com/wayland-mirror/wayland-protocols/$PROTOCOLS_VERSION/stable/xdg-shell/xdg-shell.xml" -o "$OUT/protocols/xdg-shell.xml"
printf '%s  %s\n' "$XDG_SHELL_SHA256" "$OUT/protocols/xdg-shell.xml" | shasum -a 256 -c -
curl -fsSL --retry 3 "https://raw.githubusercontent.com/wayland-mirror/wayland-protocols/$PROTOCOLS_VERSION/stable/linux-dmabuf/linux-dmabuf-v1.xml" -o "$OUT/protocols/linux-dmabuf.xml"
printf '%s  %s\n' "$DMABUF_SHA256" "$OUT/protocols/linux-dmabuf.xml" | shasum -a 256 -c -
curl -fsSL --retry 3 "https://raw.githubusercontent.com/wayland-mirror/wayland-protocols/$PROTOCOLS_VERSION/unstable/linux-explicit-synchronization/linux-explicit-synchronization-unstable-v1.xml" -o "$OUT/protocols/explicit-sync.xml"
printf '%s  %s\n' "$EXPLICIT_SYNC_SHA256" "$OUT/protocols/explicit-sync.xml" | shasum -a 256 -c -
curl -fsSL --retry 3 "https://raw.githubusercontent.com/wayland-mirror/wayland-protocols/$PROTOCOLS_VERSION/stable/presentation-time/presentation-time.xml" -o "$OUT/protocols/presentation-time.xml"
printf '%s  %s\n' "$PRESENTATION_TIME_SHA256" "$OUT/protocols/presentation-time.xml" | shasum -a 256 -c -
mkdir -p "$OUT/generated" "$OUT/ffi-build"
(
    cd "$OUT/ffi-build"
    CC="$TOOLS/aarch64-linux-android35-clang" AR="$TOOLS/llvm-ar" RANLIB="$TOOLS/llvm-ranlib" \
    CFLAGS='-O2 -fPIC' "$OUT/ffi/configure" --host=aarch64-linux-android --prefix="$OUT/ffi-install" \
        --disable-shared --enable-static --disable-docs --disable-multi-os-directory
    make -j"$(getconf _NPROCESSORS_ONLN)"
    make install
)
cat > "$OUT/wayland/config.h" <<'CONFIG'
#define PACKAGE "wayland"
#define PACKAGE_VERSION "1.24.0"
#define HAVE_ACCEPT4 1
#define HAVE_MKOSTEMP 1
#define HAVE_POSIX_FALLOCATE 1
#define HAVE_PRCTL 1
#define HAVE_MEMFD_CREATE 1
#define HAVE_MREMAP 1
#define HAVE_STRNDUP 1
#define HAVE_SYS_PRCTL_H 1
#define HAVE_XUCRED_CR_PID 0
#define HAVE_BROKEN_MSG_CMSG_CLOEXEC 0
CONFIG
sed -e 's/@WAYLAND_VERSION_MAJOR@/1/g' -e 's/@WAYLAND_VERSION_MINOR@/24/g' \
    -e 's/@WAYLAND_VERSION_MICRO@/0/g' -e 's/@WAYLAND_VERSION@/1.24.0/g' \
    "$OUT/wayland/src/wayland-version.h.in" > "$OUT/generated/wayland-version.h"
# The scanner runs on the build host. Expat is a host dependency, never in the APK.
cc -O2 -DHAVE_STRNDUP=1 -I"$OUT/wayland/src" -I"$OUT/generated" \
    "$OUT/wayland/src/scanner.c" "$OUT/wayland/src/wayland-util.c" -lexpat -o "$OUT/scanner"
for side in server client; do
    "$OUT/scanner" "$side-header" "$OUT/wayland/protocol/wayland.xml" "$OUT/generated/wayland-$side-protocol.h"
    "$OUT/scanner" -c "$side-header" "$OUT/wayland/protocol/wayland.xml" "$OUT/generated/wayland-$side-protocol-core.h"
    for protocol in xdg-shell linux-dmabuf explicit-sync presentation-time; do
        "$OUT/scanner" "$side-header" "$OUT/protocols/$protocol.xml" "$OUT/generated/$protocol-$side.h"
    done
done
"$OUT/scanner" public-code "$OUT/wayland/protocol/wayland.xml" "$OUT/generated/wayland-protocol.c"
for protocol in xdg-shell linux-dmabuf explicit-sync presentation-time; do
    "$OUT/scanner" private-code "$OUT/protocols/$protocol.xml" "$OUT/generated/$protocol-protocol.c"
done
