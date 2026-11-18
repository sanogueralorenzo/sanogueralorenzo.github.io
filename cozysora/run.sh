#!/bin/sh
# Build and launch from a canonical path so Godot's C# script paths stay portable.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
if [ -z "${DOTNET_ROOT:-}" ] && [ -x "$HOME/.dotnet/dotnet" ]; then
    export DOTNET_ROOT="$HOME/.dotnet"
fi
if [ -n "${DOTNET_ROOT:-}" ]; then
    export PATH="$DOTNET_ROOT:$PATH"
fi
if ! command -v dotnet >/dev/null 2>&1; then
    echo "Install the .NET 10 SDK, or set DOTNET_ROOT to its installation directory." >&2
    exit 1
fi
if [ -n "${GODOT_BIN:-}" ]; then
    engine=$GODOT_BIN
elif command -v godot-mono >/dev/null 2>&1; then
    engine=godot-mono
elif [ -x /Applications/Godot_mono.app/Contents/MacOS/Godot ]; then
    engine=/Applications/Godot_mono.app/Contents/MacOS/Godot
elif [ -x "$HOME/.local/share/cozysora-tools/Godot_mono.app/Contents/MacOS/Godot" ]; then
    engine="$HOME/.local/share/cozysora-tools/Godot_mono.app/Contents/MacOS/Godot"
else
    engine=godot
fi
case "$("$engine" --version)" in
    4.7.2.*.mono.*) ;;
    *) echo "Use Godot 4.7.2 .NET; set GODOT_BIN to its executable." >&2; exit 1 ;;
esac
cd "$project_dir"
dotnet build CozySora.csproj --nologo
# Prepare project-owned previews and script metadata on fresh checkouts too.
"$engine" --headless --path "$project_dir" --import
exec "$engine" --path "$project_dir" "$@"
