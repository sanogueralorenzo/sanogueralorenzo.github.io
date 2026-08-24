#!/usr/bin/env bash
set -euo pipefail

aeolian_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
aeolian_godot_bin="${AEOLIAN_GODOT_BIN:-godot}"
aeolian_capture_dir="$aeolian_root/reports/visual-smoke"
aeolian_visual_log="$(mktemp)"

trap 'rm -f "$aeolian_visual_log"' EXIT

"$aeolian_godot_bin" --path "$aeolian_root" -- --capture-smoke \
  2>&1 | tee "$aeolian_visual_log"

if rg -q 'SCRIPT ERROR:|ERROR:|ObjectDB .* leaked at exit' "$aeolian_visual_log"; then
  echo "Visual smoke reported a Godot error or teardown leak." >&2
  exit 1
fi

for aeolian_capture in \
  title.png \
  course.png \
  course-speed.png \
  recovery.png \
  pause.png \
  crash.png; do
  if [[ ! -s "$aeolian_capture_dir/$aeolian_capture" ]]; then
    echo "Missing or empty visual-smoke capture: $aeolian_capture" >&2
    exit 1
  fi
done

echo "Native Forward+ visual smoke passed."
