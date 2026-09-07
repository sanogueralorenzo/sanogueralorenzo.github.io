#!/bin/sh
set -eu
rewrite_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$rewrite_root"
mkdir -p build/tests
swiftc -parse-as-library Sources/Editing.swift Sources/Preview.swift Sources/Shortcut.swift tests/PreviewRuntime.swift \
  -o build/tests/PreviewRuntime -framework AppKit -framework Carbon
build/tests/PreviewRuntime "$rewrite_root/build/tests/preview.png"
