#!/bin/sh
set -eu
clipboard_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/clipboard-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
swiftc "$clipboard_root/Sources/ClipboardHistory.swift" "$clipboard_root/tests/ClipboardHistoryTests.swift" -o "$test_dir/history-tests"
"$test_dir/history-tests"
swiftc "$clipboard_root/Sources/ClipboardHistory.swift" "$clipboard_root/Sources/ClipboardFormats.swift" "$clipboard_root/tests/ClipboardFormatsTests.swift" -o "$test_dir/formats-tests"
"$test_dir/formats-tests"
swiftc "$clipboard_root/Sources/ClipboardHistory.swift" "$clipboard_root/Sources/ClipboardFormats.swift" "$clipboard_root/Sources/ClipboardMenu.swift" "$clipboard_root/tests/ClipboardSearchTests.swift" -o "$test_dir/search-tests"
"$test_dir/search-tests"
