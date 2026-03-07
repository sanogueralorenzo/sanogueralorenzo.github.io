#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="${1:-$HOME/.local/bin}"

if ! command -v swift >/dev/null 2>&1; then
  echo "Error: Swift is not installed or not on PATH." >&2
  echo "Install Swift first, then re-run this script." >&2
  exit 1
fi

if ! command -v bash >/dev/null 2>&1; then
  echo "Error: bash is not available on PATH." >&2
  exit 1
fi

cd "$ROOT_DIR"
swift build -c release --product codex-auth >/dev/null
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/codex-auth"

mkdir -p "$DEST_DIR"
cp "$BIN_PATH" "$DEST_DIR/codex-auth"
chmod +x "$DEST_DIR/codex-auth"

echo "Installed CLI: $DEST_DIR/codex-auth"

case ":$PATH:" in
  *":$DEST_DIR:"*)
    ;;
  *)
    echo "Your PATH does not include $DEST_DIR"
    echo "Add it with: export PATH=\"$DEST_DIR:\$PATH\""
    ;;
esac
