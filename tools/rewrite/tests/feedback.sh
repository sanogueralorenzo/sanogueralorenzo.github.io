#!/bin/sh
set -eu
rewrite_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$rewrite_root"
mkdir -p build/tests
swiftc -parse-as-library Sources/Editing.swift Sources/Selection.swift Sources/ActionMenu.swift Sources/MenuBarStatus.swift Sources/Shortcut.swift Sources/Settings.swift Sources/RewriteConfiguration.swift tests/FeedbackRuntime.swift \
  -o build/tests/FeedbackRuntime -framework AppKit -framework Carbon
build/tests/FeedbackRuntime "$rewrite_root/build/tests/feedback" "$@"
