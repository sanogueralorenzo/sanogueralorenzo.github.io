#!/usr/bin/env bash
set -euo pipefail
: "${NDK:?Set NDK to the pinned Android NDK}"
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
case "$(uname -s)" in
    Darwin) HOST=darwin-x86_64 ;;
    Linux) HOST=linux-x86_64 ;;
    *) exit 1 ;;
esac
TOOLS="$NDK/toolchains/llvm/prebuilt/$HOST"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
SYSROOT="$WORK/sysroot"
mkdir -p "$SYSROOT"
extract_deb() {
    curl -fsSL --retry 3 "https://snapshot.ubuntu.com/ubuntu/20261005T120000Z/pool/main/g/glibc/$1" -o "$WORK/package.deb"
    printf '%s  %s\n' "$2" "$WORK/package.deb" | shasum -a 256 -c -
    (cd "$WORK"; ar -x package.deb data.tar.zst; tar -xf data.tar.zst -C "$SYSROOT")
}
extract_deb libc6-dev_2.39-0ubuntu8.9_arm64.deb 9bf6acb8a3433ffe561182517640970d324425fabbbeb54a24d737ba1f3c816b
extract_deb libc6_2.39-0ubuntu8.9_arm64.deb ad109797c5f78a5eeb6d4c296bfbaae68b239111a0c9ac0eb97b8d430284ac45
LIB="$SYSROOT/usr/lib/aarch64-linux-gnu"
BUILTINS="$("$TOOLS/bin/clang" -print-resource-dir)/lib/linux/libclang_rt.builtins-aarch64-android.a"
# Keep GNU libc headers ahead of the NDK's Linux UAPI headers.
cat > "$WORK/cc" <<COMPILER
#!/usr/bin/env bash
exec "$TOOLS/bin/clang" --target=aarch64-linux-gnu --sysroot="$SYSROOT" \\
 -isystem "$SYSROOT/usr/include" -isystem "$SYSROOT/usr/include/aarch64-linux-gnu" \\
 -isystem "$TOOLS/sysroot/usr/include/aarch64-linux-android" -isystem "$TOOLS/sysroot/usr/include" \\
 -mno-outline-atomics -fuse-ld=lld -nostdlib "$LIB/crt1.o" "$LIB/crti.o" \\
 "\$@" "$BUILTINS" "$LIB/libc.so.6" "$LIB/libc_nonshared.a" "$LIB/crtn.o" \\
 -Wl,--dynamic-linker=/lib/ld-linux-aarch64.so.1
COMPILER
chmod +x "$WORK/cc"

# GNU/Linux libraries, independent of Android's Bionic engines.
shared_library() {
    local library=$1
    shift
    "$TOOLS/bin/clang" --target=aarch64-linux-gnu --sysroot="$SYSROOT" \
    -isystem "$SYSROOT/usr/include" -isystem "$SYSROOT/usr/include/aarch64-linux-gnu" \
    -isystem "$TOOLS/sysroot/usr/include/aarch64-linux-android" -isystem "$TOOLS/sysroot/usr/include" \
    -O2 -fPIC -mno-outline-atomics -fuse-ld=lld -nostdlib -shared \
    "$LIB/crti.o" "$@" "$BUILTINS" \
    "$LIB/libc.so.6" "$LIB/libc_nonshared.a" "$LIB/crtn.o" \
    -Wl,-soname,"$library" -Wl,-z,max-page-size=16384 -o "$OUT/$library"
}
shared_library libxbox-udev.so "$HERE/../session/xbox_udev.c"
shared_library libdeck-drm.so "$HERE/../session/drm.c"
shared_library libdeck-ports.so "$HERE/../session/socket_ports.c"
"$WORK/cc" -O2 "$HERE/../session/socket_peer.c" -o "$OUT/steam-socket-peer"
shared_library libdeck-robust.so "$HERE/../session/robust.c" "$HERE/../session/syscall.S"
shared_library libsteam-wine-memory.so "$HERE/../session/wine_memory.c"
shared_library libsteam-ui-pipe.so "$HERE/../session/steam_ui_pipe.c"

# Xbox bridge: static C++ avoids Steam's private libstdc++ ABI. GCC stays on the build host.
IFS=$'\t' read -r _ _ GCC_ARCHIVE _ GCC_SHA < "$HERE/../runtime/mesa/packages.tsv"
GCC_PACKAGE="$OUT/gcc-build.pkg.tar.xz"
if ! test -f "$GCC_PACKAGE" || ! printf '%s  %s\n' "$GCC_SHA" "$GCC_PACKAGE" | shasum -a 256 -c - >/dev/null 2>&1; then
    curl -fsSL --retry 3 "https://ca.us.mirror.archlinuxarm.org/aarch64/$GCC_ARCHIVE" -o "$GCC_PACKAGE"
fi
printf '%s  %s\n' "$GCC_SHA" "$GCC_PACKAGE" | shasum -a 256 -c -
mkdir "$WORK/gcc"
tar -xJf "$GCC_PACKAGE" -C "$WORK/gcc" usr/include/c++ usr/lib/libstdc++.a usr/lib/gcc
CXX_HEADERS=$(find "$WORK/gcc/usr/include/c++" -mindepth 1 -maxdepth 1 -type d)
GCC_LIB=$(find "$WORK/gcc/usr/lib/gcc/aarch64-unknown-linux-gnu" -mindepth 1 -maxdepth 1 -type d)
"$TOOLS/bin/clang++" --target=aarch64-linux-gnu --sysroot="$SYSROOT" \
    -isystem "$CXX_HEADERS" -isystem "$CXX_HEADERS/aarch64-unknown-linux-gnu" \
    -isystem "$SYSROOT/usr/include" -isystem "$SYSROOT/usr/include/aarch64-linux-gnu" \
    -isystem "$TOOLS/sysroot/usr/include/aarch64-linux-android" -isystem "$TOOLS/sysroot/usr/include" \
    -O2 -fPIC -mno-outline-atomics -fuse-ld=lld -nostdlib -shared -std=c++17 -pthread \
    -Wall -Wno-pointer-bool-conversion -fvisibility=hidden -fvisibility-inlines-hidden "$LIB/crti.o" "$GCC_LIB/crtbeginS.o" \
    "$HERE/../session/xbox_evdev.cpp" -Wl,--start-group "$WORK/gcc/usr/lib/libstdc++.a" \
    "$GCC_LIB/libgcc.a" "$GCC_LIB/libgcc_eh.a" -Wl,--end-group \
    "$LIB/libm.so.6" "$LIB/libc.so.6" "$LIB/libc_nonshared.a" "$GCC_LIB/crtendS.o" "$LIB/crtn.o" \
    -Wl,--exclude-libs,ALL -Wl,--version-script="$HERE/../session/xbox_evdev.map" -Wl,-z,max-page-size=16384 -Wl,-soname,libxbox-evdev.so \
    -o "$OUT/libxbox-evdev.so"
"$TOOLS/bin/llvm-strip" --strip-unneeded "$OUT/libxbox-evdev.so"
