#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if command -v godot >/dev/null 2>&1; then
    exec godot --path "$project_dir" "$@"
elif command -v godot4 >/dev/null 2>&1; then
    exec godot4 --path "$project_dir" "$@"
elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
    exec /Applications/Godot.app/Contents/MacOS/Godot --path "$project_dir" "$@"
else
    printf '%s\n' 'Godot 4 is required. Open project.godot in your Godot editor.' >&2
    exit 1
fi
