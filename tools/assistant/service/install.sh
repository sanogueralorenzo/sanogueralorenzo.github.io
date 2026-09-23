#!/bin/sh
set -eu

assistant_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
workspace_dir=$(CDPATH= cd -- "$assistant_dir/../.." && pwd)
node_bin=$(command -v node)
service_name=dev.sanogueralorenzo.assistant

if [ "$(uname -s)" = Darwin ]; then
  target="$HOME/Library/LaunchAgents/$service_name.plist"
  mkdir -p "$(dirname "$target")" "$HOME/Library/Logs"
  cat > "$target" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$service_name</string>
  <key>ProgramArguments</key><array><string>$node_bin</string><string>--experimental-strip-types</string><string>$assistant_dir/src/server.ts</string></array>
  <key>WorkingDirectory</key><string>$assistant_dir</string>
  <key>EnvironmentVariables</key><dict><key>ASSISTANT_WORKSPACE</key><string>$workspace_dir</string></dict>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/assistant.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/assistant-error.log</string>
</dict></plist>
EOF
  launchctl bootout "gui/$(id -u)" "$target" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$target"
  echo "Assistant installed at http://127.0.0.1:4180"
elif [ "$(uname -s)" = Linux ]; then
  target="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$service_name.service"
  mkdir -p "$(dirname "$target")"
  cat > "$target" <<EOF
[Unit]
Description=Assistant local Pi service

[Service]
Type=simple
WorkingDirectory=$assistant_dir
Environment=ASSISTANT_WORKSPACE=$workspace_dir
ExecStart=$node_bin --experimental-strip-types $assistant_dir/src/server.ts
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now "$service_name.service"
  echo "Assistant installed at http://127.0.0.1:4180"
else
  echo "Only macOS and Linux are supported" >&2
  exit 1
fi
