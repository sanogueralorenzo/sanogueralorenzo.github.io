#!/usr/bin/env bash
set -euo pipefail

aeolian_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
aeolian_godot_bin="${AEOLIAN_GODOT_BIN:-godot}"
aeolian_check_log="$(mktemp)"
trap 'rm -f "$aeolian_check_log"' EXIT

run_godot_check() {
  : > "$aeolian_check_log"
  "$aeolian_godot_bin" "$@" 2>&1 | tee "$aeolian_check_log"
  if rg -q 'SCRIPT ERROR:|ERROR:' "$aeolian_check_log"; then
    echo "Godot reported an error even though its process exit code was zero." >&2
    return 1
  fi
}

run_godot_check --headless --path "$aeolian_root" --editor --quit-after 3
run_godot_check --headless --path "$aeolian_root" --script res://tests/test_runner.gd
run_godot_check --headless --path "$aeolian_root" -- --smoke-test

echo "AEOLIAN foundation checks passed."

