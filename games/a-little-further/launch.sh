#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${ALF_TOOLS_DIR:-$HOME/.local/share/a-little-further-tools}"
DOTNET_BIN="${ALF_DOTNET:-$TOOLS_DIR/dotnet/dotnet}"
GODOT_BIN="${ALF_GODOT:-$TOOLS_DIR/A Little Further.app/Contents/MacOS/Godot}"
if [[ ! -f "$PROJECT_DIR/Local/PrivateSources.cs" ]]; then
  "$PROJECT_DIR/tools/restore-local.sh"
fi
if [[ ! -x "$DOTNET_BIN" ]]; then DOTNET_BIN="$(command -v dotnet || true)"; fi
if [[ ! -x "$GODOT_BIN" ]]; then GODOT_BIN="$(command -v godot-mono || true)"; fi
if [[ ! -x "$DOTNET_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo 'Godot .NET 4.7.2 and .NET SDK 10 are required. Set ALF_GODOT and ALF_DOTNET to their executables.' >&2
  exit 1
fi
export DOTNET_ROOT="$(dirname -- "$DOTNET_BIN")"
python3 "$PROJECT_DIR/tools/verify-local.py"
if [[ "${1:-}" == '--check' ]]; then
  exec "$DOTNET_BIN" run --project "$PROJECT_DIR/tests/CoreChecks.csproj"
fi
"$DOTNET_BIN" build "$PROJECT_DIR/ALittleFurther.csproj" --nologo
ALF_PREVIOUS_ARG=""
for ALF_ARGUMENT in "$@"; do
  if [[ "$ALF_PREVIOUS_ARG" == '--write-movie' ]]; then mkdir -p -- "$(dirname -- "$ALF_ARGUMENT")"; fi
  ALF_PREVIOUS_ARG="$ALF_ARGUMENT"
done
exec "$GODOT_BIN" --path "$PROJECT_DIR" "$@"
