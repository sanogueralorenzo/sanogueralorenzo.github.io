#!/bin/sh
set -eu
rewrite_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$rewrite_root"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/rewrite-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
swiftc -parse-as-library Sources/Editing.swift Sources/RewriteClipboard.swift Sources/SelectedText.swift Sources/RewriteProvider.swift \
  Sources/PiEnvironment.swift Sources/PiService.swift Sources/PiRPC.swift Sources/PiProcess.swift \
  Sources/AppMenu.swift Sources/RewriteController.swift \
  tests/*.swift -o "$test_dir/CoreTests" -framework AppKit
"$test_dir/CoreTests"
