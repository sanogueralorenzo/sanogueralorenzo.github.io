#!/usr/bin/env bash
set -euo pipefail

RUN_USER="${SUDO_USER:-$(id -un)}"
RUN_HOME="$(getent passwd "$RUN_USER" | awk -F: '{print $6}')"
RUN_HOME="${RUN_HOME:-$HOME}"

OPENCODE_BIN="$RUN_HOME/.opencode/bin/opencode"
OPENCODE_SERVICE_FILE="/etc/systemd/system/opencode-web.service"
OPENCODE_HOST="127.0.0.1"
OPENCODE_PORT="4096"

AUTO_UPDATE_SCRIPT="/usr/local/bin/auto-update.sh"
AUTO_UPDATE_SERVICE="/etc/systemd/system/auto-update.service"
AUTO_UPDATE_TIMER="/etc/systemd/system/auto-update.timer"
AUTO_UPDATE_TIME="*-*-* 06:00:00"

AGENTS_SKILLS_DIR="$RUN_HOME/.agents/skills"

SKILL_PRESETS=(
  "https://github.com/blader/humanizer"
)

require_sudo() {
  sudo -v
}

run_as_user() {
  # Run as user specific commands to prevent accidentally installing as root
  sudo -u "$RUN_USER" -H env HOME="$RUN_HOME" USER="$RUN_USER" bash -lc "$1"
}

install_core_packages() {
  # Base OS updates and utilities required by installers.
  sudo apt update
  sudo apt upgrade -y
  sudo apt install -y curl ca-certificates
}

install_git_tools() {
  # Git tooling for repo access and large file support.
  sudo apt install -y git git-lfs gh
  run_as_user "git lfs install"
}

install_tailscale() {
  # Secure networking for remote access to the OpenCode web UI.
  curl -fsSL https://tailscale.com/install.sh | sh
}

install_opencode() {
  # Install OpenCode CLI to enable an AI first terminal.
  run_as_user "curl -fsSL https://opencode.ai/install | bash"
}

setup_opencode_service() {
  # Systemd unit to keep OpenCode web running on boot.
  sudo tee "$OPENCODE_SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=OpenCode Web

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_USER
Environment=HOME=$RUN_HOME
WorkingDirectory=$RUN_HOME
ExecStart=$OPENCODE_BIN web --hostname $OPENCODE_HOST --port $OPENCODE_PORT
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now opencode-web.service
}

setup_agent_dirs() {
  run_as_user "mkdir -p \"$AGENTS_SKILLS_DIR\""

  for repo_url in "${SKILL_PRESETS[@]}"; do
    dest="$AGENTS_SKILLS_DIR/${repo_url##*/}"
    dest="${dest%.git}"

    run_as_user "[ -d \"$dest/.git\" ] \
      && git -C \"$dest\" pull --ff-only \
      || git clone \"$repo_url\" \"$dest\"" \
    || echo "WARN: failed to sync $dest" >&2
  done
}

print_post_install() {
  # Human-friendly reminders for first-time setup.
  echo
  echo "=============================================="
  echo "One-time manual steps (required):"
  echo
  echo "1) Authenticate Tailscale for remote access:"
  echo "     sudo tailscale up"
  echo "     sudo tailscale serve --http=4096 http://127.0.0.1:4096"
  echo
  echo "2) Authenticate GitHub for repo access:"
  echo "     gh auth login"
  echo
  echo "3) Connect OpenCode to your model:"
  echo "   Run:"
  echo "     opencode"
  echo "     /connect"
  echo "=============================================="
  echo
  echo "OpenCode Web will start automatically on boot."
  echo "Access from any Tailscale device:"
  echo "  http://<tailscale-ip>:$OPENCODE_PORT"
}

main() {
  require_sudo
  install_core_packages
  install_git_tools
  install_tailscale
  install_opencode
  setup_opencode_service
  setup_agent_dirs
  print_post_install
}

main "$@"
