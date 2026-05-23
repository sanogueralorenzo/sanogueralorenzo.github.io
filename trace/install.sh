#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install_dir="${TRACE_INSTALL_DIR:-$HOME/.local/bin}"
target="$install_dir/trace"

mkdir -p "$install_dir"
ln -sf "$script_dir/bin/trace.mjs" "$target"

printf 'Installed trace -> %s\n' "$target"
