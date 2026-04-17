#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_EXECUTABLE_NAME="CodexMenuBar"
APP_DISPLAY_NAME="Codex Menu Bar"
APP_BUNDLE_IDENTIFIER="io.github.sanogueralorenzo.codex.menubar"
APP_BUNDLE_NAME="Codex Menu Bar"
APP_DIR="$ROOT_DIR/release/$APP_BUNDLE_NAME.app"
TARGET_APP_DIR="/Applications/$APP_BUNDLE_NAME.app"
ICON_PATH="$ROOT_DIR/assets/codex.svg"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/$APP_BUNDLE_IDENTIFIER.plist"
LAUNCHD_DOMAIN="gui/$(id -u)"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script packages a macOS .app and must be run on macOS." >&2
  exit 1
fi

stop_running_app() {
  launchctl bootout "$LAUNCHD_DOMAIN" "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true
  osascript -e "tell application \"$APP_BUNDLE_NAME\" to quit" >/dev/null 2>&1 || true
  pkill -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1 || true

  local attempts=0
  while pgrep -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if (( attempts == 20 )); then
      pkill -KILL -x "$APP_EXECUTABLE_NAME" >/dev/null 2>&1 || true
    elif (( attempts > 30 )); then
      echo "Failed to stop existing $APP_EXECUTABLE_NAME process." >&2
      exit 1
    fi
    sleep 0.1
  done
}

relaunch_installed_app() {
  if [[ -f "$LAUNCH_AGENT_PLIST" ]]; then
    if launchctl bootstrap "$LAUNCHD_DOMAIN" "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1; then
      echo "Opened app: $TARGET_APP_DIR"
      return
    fi
  fi

  open "$TARGET_APP_DIR" >/dev/null 2>&1 || true
  echo "Opened app: $TARGET_APP_DIR"
}

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
  <string>14.0</string>
</dict>
</plist>
PLIST

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_EXECUTABLE_NAME"

cp "$ICON_PATH" "$APP_DIR/Contents/Resources/codex.svg"

codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Created app bundle: $APP_DIR"
stop_running_app

install_without_sudo() {
  rm -rf "$TARGET_APP_DIR"
  ditto "$APP_DIR" "$TARGET_APP_DIR"
}

install_with_sudo() {
  sudo rm -rf "$TARGET_APP_DIR"
  sudo ditto "$APP_DIR" "$TARGET_APP_DIR"
}

if install_without_sudo >/dev/null 2>&1; then
  echo "Installed app: $TARGET_APP_DIR"
else
  echo "Installing to /Applications requires admin access."
  if command -v sudo >/dev/null 2>&1 && sudo -v; then
    if install_with_sudo >/dev/null 2>&1; then
      echo "Installed app: $TARGET_APP_DIR"
    else
      echo "Failed to install to /Applications." >&2
      echo "Drag /release/Codex Menu Bar.app to /Applications" >&2
      exit 1
    fi
  else
    echo "Failed to install to /Applications." >&2
    echo "Drag /release/Codex Menu Bar.app to /Applications" >&2
    exit 1
  fi
fi

relaunch_installed_app
