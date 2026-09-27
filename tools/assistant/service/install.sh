#!/bin/sh
set -eu

assistant_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node_bin=$(command -v node)
codex_bin=$(command -v codex || true)
codex_bin_dir=$(dirname "$codex_bin")
service_name=dev.sanogueralorenzo.assistant
if [ "$(uname -s)" != Darwin ]; then
  echo "Assistant service requires macOS" >&2
  exit 1
fi
if [ -z "$codex_bin" ]; then
  echo "Install the Codex CLI and sign in before installing Assistant" >&2
  exit 1
fi
if [ "$("$node_bin" -p 'process.versions.node.split(".")[0]')" -lt 26 ]; then
  echo "Assistant requires Node 26 or newer" >&2
  exit 1
fi
computer_use_bin="${CODEX_HOME:-$HOME/.codex}/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
if [ ! -x "$computer_use_bin" ]; then
  echo "Install and enable the Codex Computer Use plugin in the desktop app before installing Assistant" >&2
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
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$codex_bin_dir:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/assistant.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/assistant-error.log</string>
</dict></plist>
EOF
launchctl bootout "gui/$(id -u)" "$target" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$target"
echo "Assistant installed at http://127.0.0.1:4180"
