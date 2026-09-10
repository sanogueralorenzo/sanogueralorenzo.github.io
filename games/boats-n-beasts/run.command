#!/bin/zsh
set -e
cd -- "${0:A:h}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$DOTNET_ROOT:$PATH"
if [[ -n "$GODOT_BIN" ]]; then
  engine="$GODOT_BIN"
elif [[ -x /Applications/Godot_mono.app/Contents/MacOS/Godot ]]; then
  engine=/Applications/Godot_mono.app/Contents/MacOS/Godot
elif [[ -x "$HOME/AndroidStudioProjects/sanogueralorenzo.github.io/games/sno-godot-local/toolchain/Godot_mono.app/Contents/MacOS/Godot" ]]; then
  engine="$HOME/AndroidStudioProjects/sanogueralorenzo.github.io/games/sno-godot-local/toolchain/Godot_mono.app/Contents/MacOS/Godot"
else
  engine=godot-mono
fi
preview_mode=false
import_resources=false
while (( $# )); do
  case "$1" in
    --preview) preview_mode=true; shift ;;
    --import) import_resources=true; shift ;;
    *) break ;;
  esac
done
if $preview_mode; then set -- art-sample.tscn "$@"; fi
dotnet build --nologo --verbosity quiet
# A fresh checkout needs resource discovery; ordinary code/shader edits do not.
if $import_resources || [[ ! -f .godot/uid_cache.bin ]]; then
  "$engine" --headless --path "$PWD" --editor --import --quit
fi
exec "$engine" --path "$PWD" "$@"
