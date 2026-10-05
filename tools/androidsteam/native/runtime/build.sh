#!/usr/bin/env bash
# Assemble the pinned Arch ARM runtime. Refresh its lock with update.py separately.
set -euo pipefail
export COPYFILE_DISABLE=1
HERE=$(cd "$(dirname "$0")" && pwd)
: "${NDK:?Set NDK to 28.2.13676358 for the source-built Zink libraries}"
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
CACHE="$OUT/packages"
mkdir -p "$CACHE"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/androidsteam-runtime.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
touch "$WORK/CaseCheck"
if [ -e "$WORK/casecheck" ]; then
    echo 'Use a case-sensitive filesystem; on macOS set TMPDIR to a case-sensitive APFS volume.' >&2
    exit 1
fi
rm "$WORK/CaseCheck"
ROOT="$WORK/root"
mkdir -p "$ROOT"
fetch() {
    local url=$1 bytes=$2 checksum=$3 extension=$4
    ARCHIVE="$CACHE/$checksum.$extension"
    if [ ! -f "$ARCHIVE" ]; then
        curl -fsSL --retry 3 "$url" -o "$WORK/download"
        test "$(wc -c < "$WORK/download" | tr -d ' ')" = "$bytes"
        printf '%s  %s\n' "$checksum" "$WORK/download" | shasum -a 256 -c -
        mv "$WORK/download" "$ARCHIVE"
    fi
    test "$(wc -c < "$ARCHIVE" | tr -d ' ')" = "$bytes"
    printf '%s  %s\n' "$checksum" "$ARCHIVE" | shasum -a 256 -c -
}
while IFS=$'\t' read -r name version path bytes checksum; do
    fetch "https://ca.us.mirror.archlinuxarm.org/aarch64/$path" "$bytes" "$checksum" "pkg.tar.xz"
    if [ "$name" = mesa ]; then
        # Keep Arch provenance; replace its all-driver payload with the pinned
        # upstream source build below. The package lock omits its unused LLVM,
        # sensors and SPIR-V diagnostic dependencies.
        tar -xf "$ARCHIVE" -C "$ROOT" usr/share/licenses/mesa
    else
        tar -xf "$ARCHIVE" -C "$ROOT" --exclude=.PKGINFO --exclude=.MTREE --exclude=.INSTALL --exclude=.BUILDINFO
    fi
    find "$ROOT" -type d ! -perm -200 -exec chmod u+rwx {} +
    # Preserve build/package provenance beside licenses for this exact snapshot.
    mkdir -p "$ROOT/usr/share/androidsteam/packages/$name"
    tar -xOf "$ARCHIVE" .PKGINFO > "$ROOT/usr/share/androidsteam/packages/$name/PKGINFO"
    tar -xOf "$ARCHIVE" .BUILDINFO > "$ROOT/usr/share/androidsteam/packages/$name/BUILDINFO"
done < "$HERE/packages.tsv"
MESA_PYTHON="${MESA_PYTHON:-python3}" bash "$HERE/mesa/build.sh" "$ROOT" "$OUT/mesa"
# Arch removed GTK 2; the validated Valve client still loads its two libraries.
# Retain the Debian package's copyright/source notices with this small exception.
while IFS=$'\t' read -r name version url bytes checksum; do
    fetch "$url" "$bytes" "$checksum" deb
    mkdir -p "$WORK/gtk2"
    (cd "$WORK/gtk2"; ar -x "$ARCHIVE"; tar -xf data.tar.*)
    cp -a "$WORK/gtk2/usr/share/doc/$name" "$ROOT/usr/share/androidsteam/packages/"
    for library in gtk gdk; do
        cp "$WORK/gtk2/usr/lib/aarch64-linux-gnu/lib$library-x11-2.0.so.0.2400.33" "$ROOT/usr/lib/"
        ln -s "lib$library-x11-2.0.so.0.2400.33" "$ROOT/usr/lib/lib$library-x11-2.0.so.0"
    done
done < "$HERE/gtk2.tsv"
# Android supplies the audio device. Keep PulseAudio's established client
# protocol and PCM pipe output; other device/DSP modules are not configured.
find "$ROOT/usr/lib/pulseaudio/modules" -type f \
    ! -name module-native-protocol-unix.so ! -name libprotocol-native.so ! -name module-pipe-sink.so -delete
# Development outputs and manuals are unused at runtime. Keep licenses, package
# provenance, font/GTK/Wayland resources, CA trust policy and English messages.
rm -rf "$ROOT/usr/include" "$ROOT/usr/lib/pkgconfig" "$ROOT/usr/share/pkgconfig" "$ROOT/usr/lib/cmake" \
    "$ROOT/usr/share/man" "$ROOT/usr/share/info" "$ROOT/usr/share/gtk-doc" "$ROOT/usr/share/gir-1.0"
find "$ROOT/usr/lib" -type f -name '*.a' -delete
# Keep copyright/license/notice files even when packages install them under doc.
# Runtime users never invoke package manuals or generate locales; C.UTF-8 is
# supplied by glibc itself. Keep gconv: Steam can load encodings dynamically.
find "$ROOT/usr/share/doc" -type f \
    ! -iname 'COPYING*' ! -iname 'COPYRIGHT*' ! -iname 'LICENSE*' ! -iname 'LICENCE*' \
    ! -iname 'NOTICE*' ! -iname 'AUTHORS*' -delete
rm -rf "$ROOT/usr/share/i18n"
rm -f "$ROOT/usr/bin/localedef" "$ROOT/usr/bin/locale-gen" "$ROOT/etc/locale.gen"
# These packages are present for their libraries. Steam/Proton never invoke
# their database inspectors, standalone conversion tools or capability viewer.
# Keep the libraries, loaders and MIME resources they supply.
while IFS= read -r tool; do
    case "$tool" in ''|'#'*) continue ;; esac
    rm -f "$ROOT/usr/bin/$tool"
done < "$HERE/unused-tools.txt"
for directory in "$ROOT/usr/share/locale"/*; do
    case "$(basename "$directory")" in en|en_*) ;; *) rm -rf "$directory" ;; esac
done
# Python's interpreter and standard library stay; its tests and caches do not.
for python in "$ROOT"/usr/lib/python3.*; do
    rm -rf "$python/test" "$python/idlelib" "$python/tkinter" "$python/ensurepip" "$python/turtledemo"
    find "$python" -type d -name __pycache__ -prune -exec rm -rf {} +
done
mkdir -p "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" "$ROOT/root" "$ROOT/tmp" "$ROOT/run" "$ROOT/etc/ld.so.conf.d"
cp "$HERE/packages.tsv" "$HERE/repositories.tsv" "$HERE/seeds.txt" "$HERE/gtk2.tsv" "$HERE/unused-tools.txt" "$ROOT/usr/share/androidsteam/"
find "$ROOT" -type f ! -perm -400 -exec chmod u+r {} +
# RuntimeArchive applies private writable permissions and contained links on Android.
# Stable order, ownership, permissions and timestamps permit identical archive
# bytes from independent builds with the pinned sources and build tools.
python3 - "$ROOT" <<'PY_ARCHIVE' | xz -6 -T 4 > "$OUT/runtime.tar.xz"
from pathlib import Path
import sys
import tarfile
root = Path(sys.argv[1])
with tarfile.open(fileobj=sys.stdout.buffer, mode="w|") as archive:
    for path in sorted(root.rglob("*")):
        entry = archive.gettarinfo(str(path), str(path.relative_to(root)))
        entry.uid = entry.gid = entry.mtime = 0
        entry.uname = entry.gname = "root"
        entry.mode = 0o755 if entry.isdir() or entry.mode & 0o111 else 0o644
        if entry.isfile():
            with path.open("rb") as contents:
                archive.addfile(entry, contents)
        else:
            archive.addfile(entry)
PY_ARCHIVE
shasum -a 256 "$OUT/runtime.tar.xz"
wc -c < "$OUT/runtime.tar.xz"
du -sk "$ROOT"
