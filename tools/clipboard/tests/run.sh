#!/bin/sh
set -eu
clipboard_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$clipboard_root"
ui=false
coverage=false
for option in "$@"; do
  case "$option" in
    --ui) ui=true ;;
    --coverage) ui=true; coverage=true ;;
    *) echo "Usage: ./tests/run.sh [--ui] [--coverage]" >&2; exit 1 ;;
  esac
done
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/clipboard-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
set -- -module-name ClipboardTests Sources/ClipboardHistory.swift Sources/ClipboardFormats.swift \
  tests/ClipboardTests.swift tests/ClipboardHistoryTests.swift tests/ClipboardFormatsTests.swift
if "$ui"; then set -- "$@" -D UI_TESTS Sources/ClipboardMenu.swift tests/ClipboardSearchTests.swift; fi
if "$coverage"; then set -- "$@" -profile-generate -profile-coverage-mapping; fi
swiftc "$@" -o "$test_dir/tests"
LLVM_PROFILE_FILE="$test_dir/tests.profraw" "$test_dir/tests"

if "$coverage"; then
  # Include the app entry point and Quick Look in the denominator without launching the app.
  swiftc -module-name ClipboardTests -profile-generate -profile-coverage-mapping -parse-as-library Sources/*.swift \
    -o "$test_dir/app" -framework AppKit -framework Carbon -framework Security
  xcrun llvm-profdata merge -sparse "$test_dir/tests.profraw" -o "$test_dir/coverage.profdata"
  echo "Coverage of all production code (including UI checks):"
  xcrun llvm-cov report "$test_dir/app" -object="$test_dir/tests" \
    -instr-profile="$test_dir/coverage.profdata" -ignore-filename-regex='/tests/'
fi
