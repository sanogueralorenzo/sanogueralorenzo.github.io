#!/usr/bin/env bash
set -euo pipefail

RUN_USER="${SUDO_USER:-$(id -un)}"
RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
if [ -z "$RUN_HOME" ]; then
  RUN_HOME="$HOME"
fi

OPENCODE_BIN="$RUN_HOME/.opencode/bin/opencode"
SERVICE_FILE="/etc/systemd/system/opencode-web.service"
AUTO_UPDATE_SCRIPT="/usr/local/bin/auto-update.sh"
AUTO_UPDATE_SERVICE="/etc/systemd/system/auto-update.service"
AUTO_UPDATE_TIMER="/etc/systemd/system/auto-update.timer"
AGENTS_SKILLS_DIR="$RUN_HOME/.agents/skills"
AUTO_UPDATE_TIME="*-*-* 06:00:00"
OPENCODE_PORT="4096"
SKILL_PRESETS=(
  "https://github.com/blader/humanizer"
)

require_sudo() {
  # Validate sudo access early to avoid mid-install prompts.
  sudo -v
}

run_as_user() {
  local cmd="$1"

  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$RUN_USER" -- env HOME="$RUN_HOME" USER="$RUN_USER" bash -lc "$cmd"
  else
    su - "$RUN_USER" -c "HOME=\"$RUN_HOME\" USER=\"$RUN_USER\" bash -lc \"$cmd\""
  fi
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
  sudo tailscale up
}

install_opencode() {
  # Install OpenCode CLI to enable an AI first terminal.
  run_as_user "curl -fsSL https://opencode.ai/install | bash"
}

setup_agent_dirs() {
  # Home for external skills cloned outside this repo.
  run_as_user "mkdir -p \"$AGENTS_SKILLS_DIR\""
}

clone_skill_presets() {
  # Clone or update a curated set of skills.
  if [ "${#SKILL_PRESETS[@]}" -eq 0 ]; then
    return
  fi

  run_as_user "mkdir -p \"$AGENTS_SKILLS_DIR\""

  for repo_url in "${SKILL_PRESETS[@]}"; do
    repo_name="${repo_url##*/}"
    repo_name="${repo_name%.git}"
    dest="$AGENTS_SKILLS_DIR/$repo_name"

    if [ -d "$dest/.git" ]; then
      if ! run_as_user "git -C \"$dest\" pull --ff-only"; then
        echo "WARN: failed to update $dest" >&2
      fi
    else
      if ! run_as_user "git clone \"$repo_url\" \"$dest\""; then
        echo "WARN: failed to clone $repo_url" >&2
      fi
    fi
  done
}

setup_opencode_service() {
  # Systemd unit to keep OpenCode web running on boot.
  sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=OpenCode Web
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
Group=$RUN_USER
Environment=HOME=$RUN_HOME
WorkingDirectory=$RUN_HOME
ExecStart=$OPENCODE_BIN web --hostname 0.0.0.0 --port $OPENCODE_PORT
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now opencode-web.service
}

write_auto_update_script() {
  # Nightly updates for packages, OpenCode, and local git clones.
  sudo tee "$AUTO_UPDATE_SCRIPT" >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail

USER_NAME="$RUN_USER"
USER_HOME="$RUN_HOME"
AGENTS_SKILLS_DIR="$RUN_HOME/.agents/skills"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get upgrade -y
apt-get install -y --only-upgrade git git-lfs gh tailscale

git lfs install --skip-repo

curl -fsSL https://opencode.ai/install | bash

if [ -d "\$AGENTS_SKILLS_DIR" ]; then
  for repo in "\$AGENTS_SKILLS_DIR"/*; do
    if [ -d "\$repo/.git" ]; then
      if command -v runuser >/dev/null 2>&1; then
        if ! runuser -u "\$USER_NAME" -- git -C "\$repo" pull --ff-only; then
          echo "WARN: failed to update \$repo" >&2
        fi
      else
        if ! su - "\$USER_NAME" -c "git -C \"\$repo\" pull --ff-only"; then
          echo "WARN: failed to update \$repo" >&2
        fi
      fi
    fi
  done
fi

for repo in "\$USER_HOME"/*; do
  base="$(basename "\$repo")"
  if [[ "\$base" == .* && "\$base" != ".agents" ]]; then
    continue
  fi
  if [ -d "\$repo/.git" ]; then
    if command -v runuser >/dev/null 2>&1; then
      if ! runuser -u "\$USER_NAME" -- git -C "\$repo" pull --ff-only; then
        echo "WARN: failed to update \$repo" >&2
      fi
    else
      if ! su - "\$USER_NAME" -c "git -C \"\$repo\" pull --ff-only"; then
        echo "WARN: failed to update \$repo" >&2
      fi
    fi
  fi
done

systemctl try-restart opencode-web.service

if [ -f /var/run/reboot-required ]; then
  systemctl reboot
fi
EOF

  sudo chmod +x "$AUTO_UPDATE_SCRIPT"
}

setup_auto_update_units() {
  # Systemd units to run the nightly auto-update script.
  sudo tee "$AUTO_UPDATE_SERVICE" >/dev/null <<'EOF'
[Unit]
Description=Auto-update dependencies
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/usr/local/bin/auto-update.sh
EOF

  sudo tee "$AUTO_UPDATE_TIMER" >/dev/null <<EOF
[Unit]
Description=Nightly auto-update

[Timer]
OnCalendar=$AUTO_UPDATE_TIME
Persistent=true

[Install]
WantedBy=timers.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now auto-update.timer
}

print_post_install() {
  # Human-friendly reminders for first-time setup.
  echo
  echo "=============================================="
  echo "One-time manual steps (required):"
  echo
  echo "1) Authenticate GitHub for access to your repo:"
  echo "     gh auth login"
  echo
  echo "2) Attach OpenCode to your model/provider:"
  echo "   Run:"
  echo "     opencode"
  echo "     /connect"
  echo "=============================================="
  echo
  echo "OpenCode Web will start automatically on boot."
  echo "Auto-updates run daily at 06:00."
  echo
  echo "Access from any Tailscale device:"
  echo "  http://<tailscale-ip>:$OPENCODE_PORT"
}

main() {
  require_sudo
  install_core_packages
  install_git_tools
  clone_skill_presets
  install_tailscale
  install_opencode
  setup_agent_dirs
  setup_opencode_service
  write_auto_update_script
  setup_auto_update_units
  print_post_install
}

main "$@"
