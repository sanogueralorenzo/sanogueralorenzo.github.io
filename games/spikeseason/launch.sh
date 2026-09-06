#!/bin/sh
set -eu
# Reject incompatible overrides before starting either the game or its editor.
render_option=
for argument in "$@"; do
    if [ -n "$render_option" ]; then
        case "$render_option:$argument" in
            method:forward_plus|driver:metal|driver:vulkan|driver:d3d12) ;;
            *) printf '%s\n' 'Spike Season requires Forward+ with Metal, Vulkan, or Direct3D 12.' >&2; exit 1 ;;
        esac
        render_option=
        continue
    fi
    case "$argument" in
        --) break ;;
        --rendering-method) render_option=method ;;
        --rendering-driver) render_option=driver ;;
        --rendering-method=forward_plus|--rendering-driver=metal|--rendering-driver=vulkan|--rendering-driver=d3d12) ;;
        --rendering-method=*|--rendering-driver=*) printf '%s\n' 'Spike Season requires Forward+ with Metal, Vulkan, or Direct3D 12.' >&2; exit 1 ;;
    esac
done
if [ -n "$render_option" ]; then
    printf '%s\n' 'A rendering option is missing its value.' >&2
    exit 1
fi
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if command -v godot >/dev/null 2>&1; then
    exec godot --path "$project_dir" "$@"
elif command -v godot4 >/dev/null 2>&1; then
    exec godot4 --path "$project_dir" "$@"
elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
    exec /Applications/Godot.app/Contents/MacOS/Godot --path "$project_dir" "$@"
else
    printf '%s\n' 'Godot 4.7 or newer with Forward+ is required. Open project.godot in your Godot editor.' >&2
    exit 1
fi
