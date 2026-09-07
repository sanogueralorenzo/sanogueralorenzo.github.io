#!/bin/sh
set -eu
rewrite_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$rewrite_root"
bundle_dir=$(mktemp -d "${TMPDIR:-/tmp}/rewrite-app.XXXXXX")
trap 'rm -rf "$bundle_dir"' EXIT HUP INT TERM
app="$bundle_dir/Rewrite.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" Sources/*.swift \
  -o "$app/Contents/MacOS/Rewrite" -framework AppKit -framework Carbon
cp Resources/Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
mkdir -p "$rewrite_root/build"
rm -rf "$rewrite_root/build/Rewrite.app"
mv "$app" "$rewrite_root/build/Rewrite.app"
echo "$rewrite_root/build/Rewrite.app"
