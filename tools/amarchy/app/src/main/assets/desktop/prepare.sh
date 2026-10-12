#!/bin/bash
set -euo pipefail

# The APK supplies upstream's user seed and all packages. Android owns the
# session instead of the ISO's login, systemd and hardware provisioning.
if [[ ! -e $HOME/.local/state/amarchy/provisioned ]]; then
  cp -a --update=none /etc/skel/. "$HOME/"
  mkdir -p "$HOME/.local/state/amarchy" "$HOME/Projects" "$HOME/Documents" "$HOME/Downloads" "$HOME/Pictures" "$HOME/Videos"
  export OMARCHY_SETUP_CONTEXT=iso-chroot
  export OMARCHY_USER_NAME=Amarchy OMARCHY_USER_EMAIL=
  source "$OMARCHY_PATH/install/user/theme.sh"
  source "$OMARCHY_PATH/install/user/first-run/gnome-theme.sh"
  source "$OMARCHY_PATH/install/user/chromium.sh"
  source "$OMARCHY_PATH/install/user/xcompose.sh"
  update-desktop-database "$HOME/.local/share/applications"
  env -u BROWSER xdg-settings set default-web-browser chromium.desktop
  touch "$HOME/.local/state/amarchy/provisioned"
fi

