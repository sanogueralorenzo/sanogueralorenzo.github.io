#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_step() {
  local label="$1"
  local script_path="$2"

  echo
  echo "==> $label"
  bash "$script_path"
}

run_step "Install codex-auth CLI" "$ROOT_DIR/codex-auth/scripts/install.sh"
run_step "Install codex-app-server CLI" "$ROOT_DIR/codex-app-server/scripts/install.sh"
run_step "Install codex-remote CLI" "$ROOT_DIR/codex-remote/scripts/install.sh"
run_step "Install Codex Menu Bar app" "$ROOT_DIR/codex-menubar/scripts/install.sh"

echo
echo "All installs completed."
