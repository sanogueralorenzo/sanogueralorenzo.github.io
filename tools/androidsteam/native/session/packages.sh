#!/usr/bin/env bash
# Only the source-built Android adapters; Arch supplies the Linux session.
set -euo pipefail
export COPYFILE_DISABLE=1
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root/usr/lib" "$WORK/root/usr/bin"
cp "$2/libxbox-udev.so" "$2/libxbox-evdev.so" "$2/libdeck-drm.so" "$2/libdeck-robust.so" "$2/libdeck-ports.so" "$2/libsteam-wine-memory.so" "$2/libsteam-ui-pipe.so" "$WORK/root/usr/lib/"
cp "$2/steam-socket-peer" "$WORK/root/usr/bin/"
tar -cJf "$OUT/session-components.tar.xz" -C "$WORK/root" .
