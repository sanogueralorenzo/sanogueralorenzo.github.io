#!/bin/sh
set -eu
service_name=dev.sanogueralorenzo.agent
if [ "$(uname -s)" != Darwin ]; then
  echo "Agent service requires macOS" >&2
  exit 1
fi
target="$HOME/Library/LaunchAgents/$service_name.plist"
launchctl bootout "gui/$(id -u)" "$target" 2>/dev/null || true
rm -f "$target"
