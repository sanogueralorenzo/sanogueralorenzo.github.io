#!/usr/bin/env bash
# Adapted from DroidDeck tools/proot/build.sh (GPL-3.0); see THIRD_PARTY.md.
set -euo pipefail
: "${NDK:?Set NDK to the Android NDK directory}"
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
CC="$TOOLS/aarch64-linux-android35-clang"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fetch() {
    curl -fsSL --retry 3 "$2" -o "$WORK/$1.tar.gz"
    printf '%s  %s\n' "$3" "$WORK/$1.tar.gz" | shasum -a 256 -c -
    mkdir "$WORK/$1"
    tar -xzf "$WORK/$1.tar.gz" --strip-components=1 -C "$WORK/$1"
}
fetch proot "https://github.com/termux/proot/archive/$PROOT_COMMIT.tar.gz" "$PROOT_SHA256"
fetch talloc "https://www.samba.org/ftp/talloc/talloc-$TALLOC_VERSION.tar.gz" "$TALLOC_SHA256"
# Android Process.destroy sends SIGTERM, which upstream PRoot ignores. Reap its
# tracees on TERM; EXITKILL also kills them if the tracer dies unexpectedly.
(cd "$WORK/proot"; patch -p1 -F0 < "$HERE/session-cleanup.patch")
mkdir -p "$WORK/talloc/config" "$WORK/bin"
cp "$HERE/talloc-config.h" "$WORK/talloc/config/config.h"
"$CC" -c -O2 -fPIC -ffile-prefix-map="$WORK"=. -D__STDC_WANT_LIB_EXT1__=1 -DHAVE_CONFIG_H \
    -I"$WORK/talloc/config" -I"$WORK/talloc" -I"$WORK/talloc/lib/replace" \
    "$WORK/talloc/talloc.c" -o "$WORK/talloc.o"
"$TOOLS/llvm-ar" rcs "$WORK/libtalloc.a" "$WORK/talloc.o"
ln -s "$TOOLS/llvm-readelf" "$WORK/bin/readelf"
PATH="$WORK/bin:$PATH" make -C "$WORK/proot/src" -j"$(getconf _NPROCESSORS_ONLN)" \
    CC="$CC" STRIP="$TOOLS/llvm-strip" OBJCOPY="$TOOLS/llvm-objcopy" OBJDUMP="$TOOLS/llvm-objdump" \
    CPPFLAGS="-D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -I. -I$WORK/talloc -DARG_MAX=131072 -Wno-error=implicit-function-declaration" \
    LDFLAGS="$WORK/libtalloc.a -Wl,-z,noexecstack -Wl,-z,max-page-size=16384" \
    PROOT_UNBUNDLE_LOADER=/nonexistent proot loader
install -m755 "$WORK/proot/src/proot" "$OUT/libproot.so"
install -m755 "$WORK/proot/src/loader/loader" "$OUT/libproot-loader.so"
"$TOOLS/llvm-strip" --strip-unneeded "$OUT/libproot.so"
grep -q '^#define HAVE_SECCOMP_FILTER' "$WORK/proot/src/build.h"
grep -q '^#define HAVE_PROCESS_VM' "$WORK/proot/src/build.h"
