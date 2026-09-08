#!/bin/sh
set -eu
minutes_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$minutes_root"
stage=$(mktemp -d "${TMPDIR:-/tmp}/minutes-build.XXXXXX")
trap 'rm -rf "$stage"' EXIT HUP INT TERM
app="$stage/Minutes.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macos15.0" Sources/*.swift \
  -o "$app/Contents/MacOS/MinutesHost" -framework AppKit -framework SwiftUI -framework Carbon \
  -framework ScreenCaptureKit -framework AVFoundation -framework UserNotifications
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/*.py "$app/Contents/Resources/"
plutil -lint "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
mkdir -p build
rm -rf build/Minutes.app
mv "$app" build/Minutes.app
printf '%s\n' "$minutes_root/build/Minutes.app"
