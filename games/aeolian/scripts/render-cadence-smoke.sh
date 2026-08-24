#!/usr/bin/env bash
set -euo pipefail

aeolian_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
aeolian_godot_bin="${AEOLIAN_GODOT_BIN:-godot}"
aeolian_report_dir="$aeolian_root/reports/cadence"
aeolian_cadence_log="$(mktemp)"

trap 'rm -f "$aeolian_cadence_log"' EXIT

run_cadence_check() {
  : > "$aeolian_cadence_log"
  "$aeolian_godot_bin" "$@" 2>&1 | tee "$aeolian_cadence_log"
  if rg -q 'SCRIPT ERROR:|ERROR:|ObjectDB .* leaked at exit' "$aeolian_cadence_log"; then
    echo "Cadence check reported a Godot error or teardown leak." >&2
    return 1
  fi
}

mkdir -p "$aeolian_report_dir"
rm -f \
  "$aeolian_report_dir/cap-30.json" \
  "$aeolian_report_dir/cap-60.json" \
  "$aeolian_report_dir/cap-120.json"

for aeolian_cap in 30 60 120; do
  run_cadence_check --audio-driver Dummy --path "$aeolian_root" \
    --disable-vsync --max-fps "$aeolian_cap" -- \
    --cadence-probe "--cadence-cap=$aeolian_cap"
done

run_cadence_check --headless --path "$aeolian_root" \
  --script res://tools/verify_cadence_reports.gd
