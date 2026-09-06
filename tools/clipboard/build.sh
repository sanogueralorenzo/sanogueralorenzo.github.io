#!/bin/sh
set -eu
clipboard_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$clipboard_root"
bundle_dir=$(mktemp -d "${TMPDIR:-/tmp}/clipboard-app.XXXXXX")
trap 'rm -rf "$bundle_dir"' EXIT HUP INT TERM
app="$bundle_dir/Clipboard.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -parse-as-library Clipboard.swift ClipboardMenu.swift ClipboardPreview.swift ClipboardFormats.swift ClipboardHistory.swift \
  -o "$app/Contents/MacOS/ClipboardHost" -framework AppKit -framework Carbon -framework Security
swift GenerateIcon.swift "$bundle_dir/Clipboard.iconset"
iconutil -c icns "$bundle_dir/Clipboard.iconset" -o "$app/Contents/Resources/Clipboard.icns"
cp Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
mkdir -p "$clipboard_root/build"
rm -rf "$clipboard_root/build/Clipboard.app"
mv "$app" "$clipboard_root/build/Clipboard.app"
echo "$clipboard_root/build/Clipboard.app"
