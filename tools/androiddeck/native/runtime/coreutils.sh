#!/usr/bin/env bash
# Ubuntu's supported GNU Coreutils provider avoids Rust multicall path checks under PRoot.
set -euo pipefail
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root"
extract() {
    curl -fsSL --retry 3 "https://ports.ubuntu.com/ubuntu-ports/$1" -o "$WORK/package.deb"
    printf '%s  %s\n' "$2" "$WORK/package.deb" | shasum -a 256 -c -
    (cd "$WORK"; ar -x package.deb data.tar.zst; tar -xf data.tar.zst -C "$WORK/root")
}
extract pool/main/c/coreutils/gnu-coreutils_9.7-3ubuntu2_arm64.deb 2c45175f8c25606ec313dd1166f6f7b253fcfb3d3d722d64f88dfdf4a70e9693
extract pool/main/c/coreutils-from/coreutils-from-gnu_0.0.0~ubuntu25_all.deb 862be75c7dd5d92815f2b80149bbcf819d11d21b1dba734f62b545bc5acb0eb7
tar -cJf "$OUT/coreutils.tar.xz" -C "$WORK/root" .
