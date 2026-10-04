#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
bash "$HERE/../packages.sh" "$HERE/packages.tsv" "$WORK/root" "$OUT/../ubuntuPackages"
cp "$HERE/packages.tsv" "$WORK/root/ubuntu-packages.tsv"
cp "$HERE/sources.tsv" "$WORK/root/ubuntu-sources.tsv"
cp "$2/libdeck-drm.so" "$2/libdeck-robust.so" "$2/libdeck-ports.so" "$2/libsteam-wine-memory.so" "$WORK/root/usr/lib/aarch64-linux-gnu/"
cp "$2/steam-socket-peer" "$WORK/root/usr/bin/"
# Keep package copyright/source records with the installed components.
tar -cJf "$OUT/session-components.tar.xz" -C "$WORK/root" .
