#!/bin/bash
set -euo pipefail
source /run/user/1000/prepare.sh
python3 /run/user/1000/platform.py
exec start-hyprland -- --config /run/user/1000/hyprland.lua
