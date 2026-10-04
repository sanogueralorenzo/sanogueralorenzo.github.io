#!/usr/bin/env bash
# GNU/Linux Wayland library and debug test client. Toolchain packages stay on the build host.
set -euo pipefail
: "${NDK:?Set NDK to the pinned Android NDK}"
HERE=$(cd "$(dirname "$0")" && pwd)
DEPS=$(cd "$1" && pwd)
mkdir -p "$2"
OUT=$(cd "$2" && pwd)
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
    curl -fsSL --retry 3 "https://ports.ubuntu.com/ubuntu-ports/pool/main/g/glibc/$1" -o "$WORK/package.deb"
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
mkdir -p "$OUT/probe/arm64-v8a"
mkdir "$WORK/ffi-build"
(
    cd "$WORK/ffi-build"
    CC="$WORK/cc" AR="$TOOLS/bin/llvm-ar" RANLIB="$TOOLS/bin/llvm-ranlib" \
    CFLAGS='-O2 -fPIC' "$DEPS/ffi/configure" --host=aarch64-linux-gnu --prefix="$WORK/ffi" \
        --disable-shared --enable-static --disable-docs --disable-multi-os-directory
    make -j"$(getconf _NPROCESSORS_ONLN)" install
) > "$OUT/linux-client-build.log" 2>&1
"$WORK/cc" -O2 -I"$DEPS/wayland/src" -I"$DEPS/generated" -I"$WORK/ffi/include" \
    "$HERE/probe.c" "$DEPS/wayland/src/wayland-client.c" "$DEPS/wayland/src/connection.c" \
    "$DEPS/wayland/src/wayland-os.c" "$DEPS/wayland/src/wayland-util.c" \
    "$DEPS/generated/wayland-protocol.c" "$DEPS/generated/xdg-shell-protocol.c" \
    "$WORK/ffi/lib/libffi.a" -o "$OUT/probe/arm64-v8a/libwayland-probe.so"

# A GNU/Linux .so, independent of Android's Bionic Wayland engine.
"$TOOLS/bin/clang" --target=aarch64-linux-gnu --sysroot="$SYSROOT" \
    -isystem "$SYSROOT/usr/include" -isystem "$SYSROOT/usr/include/aarch64-linux-gnu" \
    -isystem "$TOOLS/sysroot/usr/include/aarch64-linux-android" -isystem "$TOOLS/sysroot/usr/include" \
    -O2 -fPIC -mno-outline-atomics -fuse-ld=lld -nostdlib -shared \
    -I"$DEPS/wayland/src" -I"$DEPS/generated" -I"$WORK/ffi/include" \
    "$LIB/crti.o" "$DEPS/wayland/src/wayland-client.c" "$DEPS/wayland/src/connection.c" \
    "$DEPS/wayland/src/wayland-os.c" "$DEPS/wayland/src/wayland-util.c" \
    "$DEPS/generated/wayland-protocol.c" "$WORK/ffi/lib/libffi.a" "$BUILTINS" \
    "$LIB/libc.so.6" "$LIB/libc_nonshared.a" "$LIB/crtn.o" \
    -Wl,-soname,libwayland-client.so.0 -Wl,-z,max-page-size=16384 \
    -o "$OUT/libwayland-client.so.0"
