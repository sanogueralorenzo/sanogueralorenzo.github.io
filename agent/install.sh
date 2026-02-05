#!/usr/bin/env bash
set -euo pipefail

USER_NAME="$(id -un)"
HOME_DIR="$HOME"
OPENCODE_BIN="$HOME_DIR/.opencode/bin/opencode"
WORKDIR="$HOME_DIR"
SERVICE_FILE="/etc/systemd/system/opencode-web.service"

sudo -v

# Core packages
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl ca-certificates

# Git
sudo apt install -y git git-lfs gh
git lfs install

# Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# OpenCode
curl -fsSL https://opencode.ai/install | bash

# Agent skills
mkdir -p "$HOME_DIR/.agents/skills"

# OpenCode web service
sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=OpenCode Web
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER_NAME
Group=$USER_NAME
Environment=HOME=$HOME_DIR
WorkingDirectory=$WORKDIR
ExecStart=$OPENCODE_BIN web --hostname 0.0.0.0 --port 4096
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now opencode-web.service

# Auto-update script
sudo tee /usr/local/bin/auto-update.sh >/dev/null <<EOF
#!/usr/bin/env bash
set -euo pipefail

USER_NAME="$USER_NAME"
HOME_DIR="$HOME_DIR"
AGENTS_SKILLS_DIR="\$HOME_DIR/.agents/skills"

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

systemctl try-restart opencode-web.service

if [ -f /var/run/reboot-required ]; then
  systemctl reboot
fi
EOF

sudo chmod +x /usr/local/bin/auto-update.sh

# Auto-update service and timer
sudo tee /etc/systemd/system/auto-update.service >/dev/null <<'EOF'
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

sudo tee /etc/systemd/system/auto-update.timer >/dev/null <<'EOF'
[Unit]
Description=Nightly auto-update

[Timer]
OnCalendar=*-*-* 06:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now auto-update.timer

# Post-install notes
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
echo "  http://<tailscale-ip>:4096"
