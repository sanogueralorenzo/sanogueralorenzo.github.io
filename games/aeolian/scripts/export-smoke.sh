#!/usr/bin/env bash
set -euo pipefail

aeolian_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
aeolian_godot_bin="${AEOLIAN_GODOT_BIN:-godot}"
aeolian_build_root="$(mktemp -d)"
aeolian_export_log="$(mktemp)"
trap 'rm -rf "$aeolian_build_root"; rm -f "$aeolian_export_log"' EXIT

mkdir -p "$aeolian_build_root/windows" "$aeolian_build_root/linux"

for aeolian_kind in debug release; do
	: > "$aeolian_export_log"
	"$aeolian_godot_bin" --quiet --headless --path "$aeolian_root" \
		"--export-${aeolian_kind}" "Windows Desktop" \
		"$aeolian_build_root/windows/aeolian-${aeolian_kind}.exe" \
		2>&1 | tee "$aeolian_export_log"
	if rg -q 'SCRIPT ERROR:|ERROR:' "$aeolian_export_log"; then
		echo "Windows ${aeolian_kind} export reported an error." >&2
		exit 1
	fi
	: > "$aeolian_export_log"
	"$aeolian_godot_bin" --quiet --headless --path "$aeolian_root" \
		"--export-${aeolian_kind}" "Linux" \
		"$aeolian_build_root/linux/aeolian-${aeolian_kind}.x86_64" \
		2>&1 | tee "$aeolian_export_log"
	if rg -q 'SCRIPT ERROR:|ERROR:' "$aeolian_export_log"; then
		echo "Linux ${aeolian_kind} export reported an error." >&2
		exit 1
	fi
done

file "$aeolian_build_root"/windows/* "$aeolian_build_root"/linux/*
shasum -a 256 "$aeolian_build_root"/windows/* "$aeolian_build_root"/linux/*

echo "Cross-platform export packaging smoke passed."
