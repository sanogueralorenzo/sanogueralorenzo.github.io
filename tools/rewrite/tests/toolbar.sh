#!/bin/sh
set -eu
rewrite_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$rewrite_root"
mkdir -p build/tests
swiftc -parse-as-library Sources/Editing.swift Sources/Selection.swift Sources/SelectionToolbar.swift tests/ToolbarRuntime.swift \
  -o build/tests/ToolbarRuntime -framework AppKit
build/tests/ToolbarRuntime "$rewrite_root/build/tests/toolbar.png" "$@"
