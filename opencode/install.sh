#!/usr/bin/env bash
set -euo pipefail

USER_NAME="$(id -un)"
HOME_DIR="$HOME"
OPENCODE_BIN="$HOME_DIR/.opencode/bin/opencode"
WORKDIR="$HOME_DIR/workspaces"
SERVICE_FILE="/etc/systemd/system/opencode-web.service"

sudo -v

sudo apt update
sudo apt upgrade -y
sudo apt install -y curl ca-certificates git git-lfs gh

git lfs install

curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

curl -fsSL https://opencode.ai/install | bash

mkdir -p "$WORKDIR"

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

sudo tee /usr/local/bin/opencode-auto-update.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get upgrade -y
apt-get install -y --only-upgrade git git-lfs gh tailscale

git lfs install --skip-repo

curl -fsSL https://opencode.ai/install | bash

systemctl try-restart opencode-web.service

if [ -f /var/run/reboot-required ]; then
  systemctl reboot
fi
EOF

sudo chmod +x /usr/local/bin/opencode-auto-update.sh

sudo tee /etc/systemd/system/opencode-auto-update.service >/dev/null <<'EOF'
[Unit]
Description=Auto-update OpenCode dependencies
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/usr/local/bin/opencode-auto-update.sh
EOF

sudo tee /etc/systemd/system/opencode-auto-update.timer >/dev/null <<'EOF'
[Unit]
Description=Nightly OpenCode auto-update

[Timer]
OnCalendar=*-*-* 06:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now opencode-auto-update.timer

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
