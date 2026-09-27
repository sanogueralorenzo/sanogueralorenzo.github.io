#!/bin/sh
set -eu

assistant_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node_bin=$(command -v node)
service_name=dev.sanogueralorenzo.assistant
if [ "$(uname -s)" != Darwin ]; then
  echo "Assistant service requires macOS" >&2
  exit 1
fi
computer_use_plugin="${CODEX_HOME:-$HOME/.codex}/plugins/cache/openai-bundled/unified-computer-use"
if ! find "$computer_use_plugin" -mindepth 2 -maxdepth 2 -name .mcp.json -print -quit 2>/dev/null | grep -q .; then
  echo "Install and enable the Codex Computer Use plugin before installing Assistant" >&2
  exit 1
fi

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
