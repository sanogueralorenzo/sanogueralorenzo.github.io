#!/usr/bin/env bash
# The pinned Ubuntu runtime already provides libc, libstdc++, zlib/zstd, ffi,
# BSD/MD, and GCC runtime libraries. Add only the graphics dependencies it lacks.
set -euo pipefail
export COPYFILE_DISABLE=1
HERE=$(cd "$(dirname "$0")" && pwd)
WAYLAND=$(cd "$1" && pwd)
mkdir -p "$2"
OUT=$(cd "$2" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
bash "$HERE/../packages.sh" "$HERE/packages.tsv" "$WORK/root" "$OUT/../ubuntuPackages"
mkdir -p "$WORK/root/usr/lib/aarch64-linux-gnu"
cp "$WAYLAND/libwayland-client.so.0" "$WORK/root/usr/lib/aarch64-linux-gnu/"
# Component copyright/source records are kept alongside these libraries.
cp "$HERE/packages.tsv" "$WORK/root/ubuntu-packages.tsv"
tar -cJf "$OUT/graphics-libraries.tar.xz" -C "$WORK/root" .
