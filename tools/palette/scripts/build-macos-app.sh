#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
palette_root=$(dirname "$script_dir")
cd "$palette_root"
bundle_dir=$(mktemp -d "${TMPDIR:-/tmp}/palette-app.XXXXXX")
trap 'rm -rf "$bundle_dir"' EXIT HUP INT TERM
app="$bundle_dir/Palette.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -parse-as-library native/macos/PaletteHost.swift native/macos/ClipboardSupport.swift native/macos/ClipboardStore.swift native/macos/SettingsPanel.swift \
  -o "$app/Contents/MacOS/PaletteHost" -framework AppKit -framework Carbon -framework Security
swift native/macos/GenerateIcon.swift "$bundle_dir/Palette.iconset"
iconutil -c icns "$bundle_dir/Palette.iconset" -o "$app/Contents/Resources/Palette.icns"
cp native/macos/Info.plist "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
mkdir -p "$palette_root/build"
rm -rf "$palette_root/build/Palette.app"
mv "$app" "$palette_root/build/Palette.app"
echo "$palette_root/build/Palette.app"
