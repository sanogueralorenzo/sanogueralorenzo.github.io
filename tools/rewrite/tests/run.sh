#!/bin/sh
set -eu
rewrite_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$rewrite_root"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/rewrite-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
swiftc -parse-as-library Sources/Editing.swift Sources/Selection.swift Sources/RewriteConfiguration.swift Sources/PiRequest.swift Sources/PiService.swift Sources/ProcessRunner.swift Sources/PiRPC.swift \
  tests/RewriteTests.swift -o "$test_dir/RewriteTests" -framework AppKit
"$test_dir/RewriteTests" "$@"
