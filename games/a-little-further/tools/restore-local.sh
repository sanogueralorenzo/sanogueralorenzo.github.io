#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_DIR="${ALF_SOURCE_VAULT:-$HOME/GameSourceVault/a-little-further}"
if [[ ! -f "$VAULT_DIR/runtime/runtime-manifest.json" ]]; then
  echo "The private source package is missing: $VAULT_DIR/runtime" >&2
  echo 'Recovered Steam/Sunwake code and assets are intentionally excluded from Git. Restore the owner’s local package; the game has no substitute asset mode.' >&2
  exit 1
fi
mkdir -p "$PROJECT_DIR/Local"
cp -R "$VAULT_DIR/runtime/." "$PROJECT_DIR/Local/"
python3 "$PROJECT_DIR/tools/verify-local.py"
