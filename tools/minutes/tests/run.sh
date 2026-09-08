#!/bin/sh
set -eu
minutes_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stage=$(mktemp -d "${TMPDIR:-/tmp}/minutes-tests.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
cd "$minutes_root"
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" Sources/Meeting.swift Sources/Recorder.swift Sources/MinutesModel.swift tests/MinutesTests.swift \
  -framework AppKit -framework UserNotifications -framework AVFoundation -framework ScreenCaptureKit -o "$stage/tests"
"$stage/tests"
minutes_python="${MINUTES_SUPPORT:-$HOME/Library/Application Support/Minutes}/runtime/bin/python3"
if [ ! -x "$minutes_python" ]; then minutes_python=python3; fi
"$minutes_python" -m unittest discover -s tests -p 'test_*.py' -v
