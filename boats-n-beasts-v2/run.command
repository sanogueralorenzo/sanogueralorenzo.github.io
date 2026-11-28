#!/bin/zsh
set -e
cd -- "${0:A:h}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$DOTNET_ROOT:$PATH"
if [[ -n "$GODOT_BIN" ]]; then
  engine="$GODOT_BIN"
else
  candidates=(
    "/Applications/Godot_mono.app/Contents/MacOS/Godot"
    "$HOME/Applications/Godot_mono.app/Contents/MacOS/Godot"
    "$PWD/.godot/toolchain/Godot_mono.app/Contents/MacOS/Godot"
    "${commands[godot-mono]}" "${commands[godot]}"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" && "$("$candidate" --version)" == *mono* ]]; then
      engine="$candidate"
      break
    fi
  done
  if [[ -z "$engine" ]]; then
    print -u2 'Install Godot 4.7.2 .NET or set GODOT_BIN to its executable.'
    exit 1
  fi
fi
preview_mode=false
import_resources=false
preview_once=false
while (( $# )); do
  case "$1" in
    --preview) preview_mode=true; shift ;;
    --import) import_resources=true; shift ;;
    --once) preview_once=true; shift ;;
    *) break ;;
  esac
done
dotnet build --nologo --verbosity quiet
# A fresh checkout needs resource discovery; ordinary code/shader edits do not.
if $import_resources || [[ ! -f .godot/uid_cache.bin ]]; then
  "$engine" --headless --path "$PWD" --editor --import --quit
fi
if $preview_mode; then
  if ! $preview_once; then exec python3 tools/preview.py "$engine" "$@"; fi
  set -- art-sample.tscn "$@"
fi
exec "$engine" --path "$PWD" "$@"
