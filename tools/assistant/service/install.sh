#!/bin/sh
set -eu

assistant_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node_bin=$(command -v node)
service_name=dev.sanogueralorenzo.assistant
cua_version=0.29.1
if [ "$(uname -s)" != Darwin ]; then
  echo "Assistant service requires macOS" >&2
  exit 1
fi

cua_bin="$HOME/.local/bin/cua-driver"
if [ ! -x "$cua_bin" ] || [ "$("$cua_bin" --version | awk '{print $2}')" != "$cua_version" ] || [ ! -d /Applications/CuaDriver.app ]; then
  cua_installer=$(curl -fsSL https://cua.ai/driver/install.sh)
  CUA_DRIVER_RS_VERSION="$cua_version" CUA_DRIVER_RS_NO_MODIFY_PATH=1 /bin/bash -c "$cua_installer"
fi
cua_skill="$HOME/.cua-driver/skills/cua-driver"
if [ ! -f "$cua_skill/SKILL.md" ] || [ "$(awk '$1 == "version:" {print $2}' "$cua_skill/SKILL.md")" != "$cua_version" ]; then
  "$cua_bin" skills install --agent codex
fi
if [ ! -f "$cua_skill/SKILL.md" ] || [ "$(awk '$1 == "version:" {print $2}' "$cua_skill/SKILL.md")" != "$cua_version" ]; then
  echo "Cua Driver skill does not match version $cua_version" >&2
  exit 1
fi
cua_target="$HOME/Library/LaunchAgents/com.trycua.cua-driver.plist"
if [ ! -e "$cua_target" ]; then
  mkdir -p "$(dirname "$cua_target")"
  cat > "$cua_target" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.trycua.cua-driver</string>
  <key>ProgramArguments</key><array><string>/Applications/CuaDriver.app/Contents/MacOS/cua-driver</string><string>serve</string></array>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
</dict></plist>
EOF
fi
launchctl bootout "gui/$(id -u)" "$cua_target" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$cua_target"

target="$HOME/Library/LaunchAgents/$service_name.plist"
mkdir -p "$(dirname "$target")" "$HOME/Library/Logs"
cat > "$target" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$service_name</string>
  <key>ProgramArguments</key><array><string>$node_bin</string><string>--experimental-strip-types</string><string>$assistant_dir/src/server.ts</string></array>
  <key>WorkingDirectory</key><string>$assistant_dir</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/assistant.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/assistant-error.log</string>
</dict></plist>
EOF
launchctl bootout "gui/$(id -u)" "$target" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$target"
echo "Assistant installed at http://127.0.0.1:4180"
