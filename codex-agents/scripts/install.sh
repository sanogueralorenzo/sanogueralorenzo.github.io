#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kill_pid_with_grace() {
  local pid="$1"
  kill -TERM "$pid" 2>/dev/null || return 0

  local retries=20
  while (( retries > 0 )); do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
    retries=$((retries - 1))
  done

  kill -KILL "$pid" 2>/dev/null || true
}

stop_existing_runtime() {
  if ! command -v pgrep >/dev/null 2>&1; then
    return 0
  fi

  local pid
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill_pid_with_grace "$pid"
  done < <(pgrep -f "codex-agents worker start" || true)
}

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

stop_existing_runtime

DEST_DIR="$(resolve_npm_bin_dir)"
TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/codex-agents-target}"

if ! command -v cargo >/dev/null 2>&1; then
  echo "Error: cargo is not installed or not on PATH." >&2
  exit 1
fi

cd "$ROOT_DIR"
cargo build --release --target-dir "$TARGET_DIR" >/dev/null
BIN_PATH="$TARGET_DIR/release/codex-agents"

mkdir -p "$DEST_DIR"
if [[ ! -w "$DEST_DIR" ]]; then
  echo "Error: destination is not writable: $DEST_DIR" >&2
  echo "Fix npm global prefix permissions and try again." >&2
  exit 1
fi

TMP_PATH="$DEST_DIR/.tmp-codex-agents-$$"
cp "$BIN_PATH" "$TMP_PATH"
chmod +x "$TMP_PATH"
mv -f "$TMP_PATH" "$DEST_DIR/codex-agents"

echo "Installed CLI: $DEST_DIR/codex-agents"

case ":$PATH:" in
  *":$DEST_DIR:"*) ;;
  *)
    echo "Your PATH does not include $DEST_DIR"
    echo "Add it with: export PATH=\"$DEST_DIR:\$PATH\""
    ;;
esac
