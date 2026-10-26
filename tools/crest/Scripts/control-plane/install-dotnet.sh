#!/bin/bash
# CI bootstrap using Microsoft's SDK installer. No global/system installation.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
sdk_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sdk"]["version"])' "$repo_root/CrestCore/global.json")"
sdk_directory="${CREST_DOTNET_INSTALL_DIR:-$HOME/.dotnet}"
if [[ -x "$sdk_directory/dotnet" && -d "$sdk_directory/sdk/$sdk_version" ]]; then
    echo "Crest SDK $sdk_version is installed in $sdk_directory"
    exit 0
fi
installer="$(mktemp "${TMPDIR:-/tmp}/crest-dotnet-install.XXXXXX")"
trap 'rm -f "$installer"' EXIT INT TERM HUP
curl --fail --location --retry 3 https://dot.net/v1/dotnet-install.sh --output "$installer"
bash "$installer" --version "$sdk_version" --architecture arm64 --install-dir "$sdk_directory" --no-path
