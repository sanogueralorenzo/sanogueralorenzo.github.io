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
dotnet build --nologo --verbosity quiet
"$engine" --headless --path "$PWD" --editor --import --quit
exec "$engine" --path "$PWD" "$@"
