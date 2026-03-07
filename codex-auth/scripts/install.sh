#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

if [[ $# -gt 0 ]]; then
  echo "Error: custom destination is no longer supported." >&2
  echo "This installer always targets npm global bin." >&2
  exit 1
fi

DEST_DIR="$(resolve_npm_bin_dir)"

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
if [[ ! -w "$DEST_DIR" ]]; then
  echo "Error: destination is not writable: $DEST_DIR" >&2
  echo "Fix npm global prefix permissions and try again." >&2
  exit 1
fi

TMP_PATH="$DEST_DIR/.tmp-codex-auth-$$"
cp "$BIN_PATH" "$TMP_PATH"
chmod +x "$TMP_PATH"
mv -f "$TMP_PATH" "$DEST_DIR/codex-auth"

echo "Installed CLI: $DEST_DIR/codex-auth"

case ":$PATH:" in
  *":$DEST_DIR:"*)
    ;;
  *)
    echo "Your PATH does not include $DEST_DIR"
    echo "Add it with: export PATH=\"$DEST_DIR:\$PATH\""
    ;;
esac
