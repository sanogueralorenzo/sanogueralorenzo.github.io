#!/usr/bin/env bash
set -euo pipefail

overrush_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
overrush_godot_bin="${OVERRUSH_GODOT_BIN:-godot}"
strategies=(dashbreaker ramjet stormtrail tempest_anchor arcstorm arc_orbit)
seeds=(41001 41002 48920)

for strategy in "${strategies[@]}"; do
	for seed in "${seeds[@]}"; do
		"$overrush_godot_bin" \
			--headless \
			--fixed-fps 300 \
			--path "$overrush_root" \
			--script res://tests/audit_engine_soak.gd \
			-- "$strategy" "$seed" 1200 apex_only
	done
done
