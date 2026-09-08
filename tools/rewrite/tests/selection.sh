#!/bin/sh
set -eu
rewrite_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$rewrite_root"
mkdir -p build/tests
swiftc -parse-as-library Sources/Editing.swift Sources/Selection.swift Sources/Processors.swift Sources/ProcessRunner.swift Sources/MenuBarStatus.swift Sources/ResultNotice.swift tests/SelectionRuntime.swift \
  -o build/tests/SelectionRuntime -framework AppKit
if [ "${1:-}" != --build-only ]; then build/tests/SelectionRuntime "$@"; fi
