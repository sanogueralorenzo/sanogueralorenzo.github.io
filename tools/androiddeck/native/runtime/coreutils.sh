#!/usr/bin/env bash
# Ubuntu's supported GNU Coreutils provider avoids Rust multicall path checks under PRoot.
set -euo pipefail
export COPYFILE_DISABLE=1
mkdir -p "$1"
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(cd "$1" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
bash "$HERE/../packages.sh" "$HERE/packages.tsv" "$WORK/root" "$OUT/../ubuntuPackages"
tar -cJf "$OUT/coreutils.tar.xz" -C "$WORK/root" .
