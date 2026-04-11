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

run_step "Install codex-core CLI" "$ROOT_DIR/ekkzo/cli/codex-core/scripts/install.sh"
run_step "Install codex-remote CLI" "$ROOT_DIR/ekkzo/cli/codex-remote/scripts/install.sh"
run_step "Install Codex Menu Bar app" "$ROOT_DIR/ekkzo/cli/codex-menubar/scripts/install.sh"

echo
echo "All installs completed."
