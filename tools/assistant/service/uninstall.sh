#!/bin/sh
set -eu
service_name=dev.sanogueralorenzo.assistant
if [ "$(uname -s)" = Darwin ]; then
  target="$HOME/Library/LaunchAgents/$service_name.plist"
  launchctl bootout "gui/$(id -u)" "$target" 2>/dev/null || true
  rm -f "$target"
elif [ "$(uname -s)" = Linux ]; then
  target="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$service_name.service"
  systemctl --user disable --now "$service_name.service" 2>/dev/null || true
  rm -f "$target"
  systemctl --user daemon-reload
fi
