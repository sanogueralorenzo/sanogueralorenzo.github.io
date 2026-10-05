#!/usr/bin/env bash
# Build the Linux GL/EGL/GBM libraries for the fixed Zink + Turnip path.
# GCC headers/startup objects and the protocol XML remain build-host inputs.
set -euo pipefail
export COPYFILE_DISABLE=1
: "${NDK:?Set NDK to 28.2.13676358}"
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/source.env"
ROOT=$(cd "$1" && pwd)
mkdir -p "$2"
OUT=$(cd "$2" && pwd)
MESA_PYTHON=$(command -v "${MESA_PYTHON:-python3}")
export PATH="$(dirname "$MESA_PYTHON"):$PATH"
"$MESA_PYTHON" - "$HERE/requirements.txt" <<'PY'
from importlib.metadata import version
from pathlib import Path
import sys
for pin in Path(sys.argv[1]).read_text().splitlines():
    package, expected = pin.split('==')
    if version(package) != expected:
        raise SystemExit(f'Install {pin} in the MESA_PYTHON environment before building.')
PY
case "$(uname -s)" in
    Darwin) HOST=darwin-x86_64 ;;
    Linux) HOST=linux-x86_64 ;;
    *) exit 1 ;;
esac
TOOLS="$NDK/toolchains/llvm/prebuilt/$HOST/bin"
test "$(sed -n 's/^Pkg.Revision = //p' "$NDK/source.properties")" = "$NDK_VERSION"
test "$(bison --version | head -1)" = 'bison (GNU Bison) 3.8.2'
test "$(flex --version | awk '{print $2}')" = '2.6.4'
WORK=$(mktemp -d "${TMPDIR:-/tmp}/androidsteam-mesa.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/development" "$WORK/source" "$WORK/wayland" "$WORK/host-pkgconfig"
# Refuse to silently mix a refreshed runtime lock with older build inputs.
mesa_package=$(awk -F '\t' '$1 == "mesa" {print $2}' "$HERE/../packages.tsv")
mesa_package=${mesa_package#*:}
wayland_package=$(awk -F '\t' '$1 == "wayland" {print $2}' "$HERE/../packages.tsv")
test "${mesa_package%-*}" = "$MESA_VERSION"
test "${wayland_package%-*}" = "$WAYLAND_VERSION"
test "$(awk -F '\t' '$1 == "libstdc++" {print $2}' "$HERE/../packages.tsv")" = \
     "$(awk -F '\t' '$1 == "gcc" {print $2}' "$HERE/packages.tsv")"
fetch() {
    local url=$1 checksum=$2 extension=$3
    ARCHIVE="$OUT/$checksum.$extension"
    if [ ! -f "$ARCHIVE" ]; then
        curl -fsSL --retry 3 "$url" -o "$WORK/download"
        printf '%s  %s\n' "$checksum" "$WORK/download" | shasum -a 256 -c -
        mv "$WORK/download" "$ARCHIVE"
    fi
    printf '%s  %s\n' "$checksum" "$ARCHIVE" | shasum -a 256 -c -
}
while IFS=$'\t' read -r name version path bytes checksum; do
    fetch "https://ca.us.mirror.archlinuxarm.org/aarch64/$path" "$checksum" pkg.tar.xz
    test "$(wc -c < "$ARCHIVE" | tr -d ' ')" = "$bytes"
    tar -xf "$ARCHIVE" -C "$WORK/development" --exclude=.PKGINFO --exclude=.MTREE --exclude=.INSTALL --exclude=.BUILDINFO
done < "$HERE/packages.tsv"
fetch "https://archive.mesa3d.org/mesa-$MESA_VERSION.tar.xz" "$MESA_SHA256" tar.xz
tar -xf "$ARCHIVE" --strip-components=1 -C "$WORK/source"
fetch "https://gitlab.freedesktop.org/wayland/wayland/-/releases/$WAYLAND_VERSION/downloads/wayland-$WAYLAND_VERSION.tar.xz" "$WAYLAND_SHA256" tar.xz
tar -xf "$ARCHIVE" --strip-components=1 -C "$WORK/wayland"
cat > "$WORK/wayland/config.h" <<CONFIG
#define PACKAGE "wayland"
#define PACKAGE_VERSION "$WAYLAND_VERSION"
#define HAVE_STRNDUP 1
CONFIG
IFS=. read -r wayland_major wayland_minor wayland_micro <<< "$WAYLAND_VERSION"
sed -e "s/@WAYLAND_VERSION_MAJOR@/$wayland_major/g" -e "s/@WAYLAND_VERSION_MINOR@/$wayland_minor/g" \
    -e "s/@WAYLAND_VERSION_MICRO@/$wayland_micro/g" -e "s/@WAYLAND_VERSION@/$WAYLAND_VERSION/g" \
    "$WORK/wayland/src/wayland-version.h.in" > "$WORK/wayland/wayland-version.h"
cc -O2 -DHAVE_STRNDUP=1 -I"$WORK/wayland/src" -I"$WORK/wayland" \
    "$WORK/wayland/src/scanner.c" "$WORK/wayland/src/wayland-util.c" -lexpat -o "$WORK/scanner"
cat > "$WORK/host-pkgconfig/wayland-scanner.pc" <<PC
wayland_scanner=$WORK/scanner
Name: Wayland Scanner
Description: Pinned build-host protocol scanner
Version: $WAYLAND_VERSION
PC
# Meson's cross pkg-config prefixes protocol paths with its sysroot. Make the
# XML available there during compilation, then remove this build-only input.
cp -a "$WORK/development/usr/share/wayland-protocols" "$ROOT/usr/share/"
cat > "$WORK/native.ini" <<NATIVE
[built-in options]
pkg_config_path = ['$WORK/host-pkgconfig']
NATIVE
cat > "$WORK/cross.ini" <<CROSS
[binaries]
c = ['$TOOLS/clang', '--target=aarch64-linux-gnu', '--sysroot=$ROOT', '--gcc-toolchain=$WORK/development/usr']
cpp = ['$TOOLS/clang++', '--target=aarch64-linux-gnu', '--sysroot=$ROOT', '--gcc-toolchain=$WORK/development/usr']
c_ld = 'lld'
cpp_ld = 'lld'
ar = '$TOOLS/llvm-ar'
strip = '$TOOLS/llvm-strip'
pkg-config = '$(command -v pkg-config)'
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
[properties]
needs_exe_wrapper = true
sys_root = '$ROOT'
pkg_config_libdir = ['$ROOT/usr/lib/pkgconfig', '$ROOT/usr/share/pkgconfig', '$WORK/development/usr/share/pkgconfig']
[built-in options]
c_args = ['-mno-outline-atomics', '-ffile-prefix-map=$WORK=.', '-ffile-prefix-map=$ROOT=/']
cpp_args = ['-mno-outline-atomics', '-ffile-prefix-map=$WORK=.', '-ffile-prefix-map=$ROOT=/']
c_link_args = ['-Wl,-z,max-page-size=16384', '-Wl,--build-id=sha1']
cpp_link_args = ['-Wl,-z,max-page-size=16384', '-Wl,--build-id=sha1']
CROSS
meson() { "$MESA_PYTHON" -m mesonbuild.mesonmain "$@"; }
meson setup "$WORK/build" "$WORK/source" --cross-file "$WORK/cross.ini" --native-file "$WORK/native.ini" \
    --prefix=/usr --libdir=lib --buildtype=release --wrap-mode=nodownload \
    -Dgallium-drivers=zink '-Dvulkan-drivers=[]' -Dllvm=disabled -Dplatforms=x11,wayland \
    -Dglx=dri -Dglvnd=enabled -Degl=enabled -Dgbm=enabled -Dgles1=disabled -Dgles2=enabled \
    -Dgallium-va=disabled -Dspirv-tools=disabled -Dlmsensors=disabled -Dlibunwind=disabled \
    -Dvalgrind=disabled '-Dtools=[]'
meson compile -C "$WORK/build" -j "${BUILD_JOBS:-8}"
meson install -C "$WORK/build" --destdir "$WORK/install" --no-rebuild --strip
# Only Zink is selected. Other display-controller names alias the same DRI
# loader but cannot be selected on the supported Adreno device.
find "$WORK/install/usr/lib/dri" -mindepth 1 ! -name zink_dri.so ! -name libdril_dri.so -delete
rm -rf "$WORK/install/usr/include" "$WORK/install/usr/lib/pkgconfig"
NOTICE="$WORK/install/usr/share/licenses/mesa"
mkdir -p "$NOTICE"
cp "$WORK/source/docs/license.rst" "$NOTICE/"
cp -a "$WORK/source/licenses" "$NOTICE/"
PROVENANCE="$WORK/install/usr/share/androidsteam/mesa"
mkdir -p "$PROVENANCE"
cp "$HERE/source.env" "$HERE/packages.tsv" "$HERE/requirements.txt" "$HERE/build.sh" "$PROVENANCE/"
"$TOOLS/clang" --version | head -1 > "$PROVENANCE/compiler.txt"
printf 'Target: aarch64-linux-gnu\n' >> "$PROVENANCE/compiler.txt"
# Verify the intended dependency removal before overlaying any libraries.
if "$TOOLS/llvm-readelf" -d "$WORK/install/usr/lib/libgallium-$MESA_VERSION.so" | grep -q 'NEEDED.*LLVM'; then
    echo 'Zink still depends on LLVM; refuse this runtime.' >&2
    exit 1
fi
"$MESA_PYTHON" - "$WORK/install" "$PROVENANCE/installed-files.txt" <<'PY'
from pathlib import Path
import sys
root, output = map(Path, sys.argv[1:])
output.write_text('\n'.join(sorted(str(p.relative_to(root)) for p in root.rglob('*') if p.is_file() or p.is_symlink())) + '\n')
PY
cp -a "$WORK/install/." "$ROOT/"
rm -rf "$ROOT/usr/share/wayland-protocols"
