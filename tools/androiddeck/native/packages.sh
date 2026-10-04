#!/usr/bin/env bash
# Extract checksum-pinned Ubuntu packages; callers choose the final runtime bundle.
set -euo pipefail
export COPYFILE_DISABLE=1
LIST=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
mkdir -p "$2"
ROOT=$(cd "$2" && pwd)
mkdir -p "$3"
CACHE=$(cd "$3" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
while IFS=$'\t' read -r name version path bytes checksum; do
    package="$CACHE/$checksum.deb"
    if [ ! -f "$package" ]; then
        curl -fsSL --retry 3 "https://ports.ubuntu.com/ubuntu-ports/$path" -o "$WORK/package.deb"
        test "$(wc -c < "$WORK/package.deb" | tr -d ' ')" = "$bytes"
        printf '%s  %s\n' "$checksum" "$WORK/package.deb" | shasum -a 256 -c -
        mv "$WORK/package.deb" "$package"
    fi
    test "$(wc -c < "$package" | tr -d ' ')" = "$bytes"
    printf '%s  %s\n' "$checksum" "$package" | shasum -a 256 -c -
    (cd "$WORK"; ar -x "$package" data.tar.zst; tar -xf data.tar.zst -C "$ROOT")
done < "$LIST"
