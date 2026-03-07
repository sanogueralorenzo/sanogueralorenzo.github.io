#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_SCRIPT="$ROOT_DIR/scripts/codex-remote"

resolve_npm_bin_dir() {
  if ! command -v npm >/dev/null 2>&1; then
    echo "Error: npm is required to resolve global install location." >&2
    exit 1
  fi

  local npm_prefix
  npm_prefix="$(npm config get prefix 2>/dev/null || true)"
  if [[ -z "$npm_prefix" || "$npm_prefix" == "undefined" || "$npm_prefix" == "null" ]]; then
    echo "Error: failed to resolve npm global prefix." >&2
    exit 1
  fi

  echo "$npm_prefix/bin"
}

DEST_DIR="${1:-$(resolve_npm_bin_dir)}"
DEST_PATH="$DEST_DIR/codex-remote"

if ! command -v bash >/dev/null 2>&1; then
  echo "Error: bash is not available on PATH." >&2
  exit 1
fi

if [[ ! -f "$SOURCE_SCRIPT" ]]; then
  echo "Error: missing source script at $SOURCE_SCRIPT" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
if [[ ! -w "$DEST_DIR" ]]; then
  echo "Error: destination is not writable: $DEST_DIR" >&2
  echo "Fix npm global prefix permissions or pass a writable directory explicitly." >&2
  exit 1
fi

ln -sf "$SOURCE_SCRIPT" "$DEST_PATH"
chmod +x "$SOURCE_SCRIPT"

echo "Installed CLI: $DEST_PATH -> $SOURCE_SCRIPT"

case ":$PATH:" in
  *":$DEST_DIR:"*)
    ;;
  *)
    echo "Your PATH does not include $DEST_DIR"
    echo "Add it with: export PATH=\"$DEST_DIR:\$PATH\""
    ;;
esac
