#!/usr/bin/env bash
# The pinned Ubuntu runtime already provides libc, libstdc++, zlib/zstd, ffi,
# BSD/MD, and GCC runtime libraries. Add only the graphics dependencies it lacks.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WAYLAND=$(cd "$1" && pwd)
mkdir -p "$2"
OUT=$(cd "$2" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root"
while IFS=$'\t' read -r name version path bytes checksum; do
    curl -fsSL --retry 3 "https://ports.ubuntu.com/ubuntu-ports/$path" -o "$WORK/package.deb"
    test "$(wc -c < "$WORK/package.deb" | tr -d ' ')" = "$bytes"
    printf '%s  %s\n' "$checksum" "$WORK/package.deb" | shasum -a 256 -c -
    (cd "$WORK"; ar -x package.deb data.tar.zst; tar -xf data.tar.zst -C "$WORK/root")
done < "$HERE/packages.tsv"
mkdir -p "$WORK/root/usr/lib/aarch64-linux-gnu"
cp "$WAYLAND/libwayland-client.so.0" "$WORK/root/usr/lib/aarch64-linux-gnu/"
# Component copyright/source records are kept alongside these libraries.
cp "$HERE/packages.tsv" "$WORK/root/ubuntu-packages.tsv"
tar -cJf "$OUT/graphics-libraries.tar.xz" -C "$WORK/root" .
