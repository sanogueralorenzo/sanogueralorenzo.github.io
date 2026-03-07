#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_EXECUTABLE_NAME="CodexAuthMenuBar"
APP_DISPLAY_NAME="Codex Auth"
APP_BUNDLE_IDENTIFIER="io.github.sanogueralorenzo.codexauth.menubar"
APP_DIR="$ROOT_DIR/release/$APP_EXECUTABLE_NAME.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script packages a macOS .app and must be run on macOS." >&2
  exit 1
fi

cd "$ROOT_DIR"
swift build -c release --product "$APP_EXECUTABLE_NAME" >/dev/null
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/$APP_EXECUTABLE_NAME"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Missing binary: $BIN_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$APP_BUNDLE_IDENTIFIER</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSUIElement</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
</dict>
</plist>
PLIST

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE_NAME"

codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Created app bundle: $APP_DIR"
