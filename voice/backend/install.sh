#!/usr/bin/env bash
set -euo pipefail

SERVICE_LABEL="io.github.sanogueralorenzo.voice.backend"
SYSTEMD_UNIT_NAME="voice-backend.service"
BIN_NAME="voice-backend"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
BIN_PATH="${BIN_DIR}/${BIN_NAME}"
LOG_DIR="${HOME}/.codex/voice-backend"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
LAUNCH_AGENT_PATH="${LAUNCH_AGENTS_DIR}/${SERVICE_LABEL}.plist"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
SYSTEMD_UNIT_PATH="${SYSTEMD_USER_DIR}/${SYSTEMD_UNIT_NAME}"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '[dry-run] %q' "$1"
    shift
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
    return 0
  fi
  "$@"
}

ensure_env_file() {
  if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    return 0
  fi
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '[dry-run] cp %q %q\n' "${SCRIPT_DIR}/.env.example" "${SCRIPT_DIR}/.env"
    return 0
  fi
  cp "${SCRIPT_DIR}/.env.example" "${SCRIPT_DIR}/.env"
  echo "Created ${SCRIPT_DIR}/.env from .env.example"
}

build_binary() {
  run_cmd mkdir -p "${BIN_DIR}"
  (cd "${SCRIPT_DIR}" && run_cmd go build -o "${BIN_PATH}" .)
  echo "Installed binary: ${BIN_PATH}"
}

write_launchd_plist() {
  run_cmd mkdir -p "${LAUNCH_AGENTS_DIR}" "${LOG_DIR}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '[dry-run] write %q\n' "${LAUNCH_AGENT_PATH}"
    return 0
  fi

  cat >"${LAUNCH_AGENT_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${SERVICE_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BIN_PATH}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${SCRIPT_DIR}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/out.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/err.log</string>
</dict>
</plist>
EOF
}

install_launchd() {
  write_launchd_plist
  local uid
  uid="$(id -u)"
  run_cmd launchctl bootout "gui/${uid}/${SERVICE_LABEL}" >/dev/null 2>&1 || true
  run_cmd launchctl bootstrap "gui/${uid}" "${LAUNCH_AGENT_PATH}"
  run_cmd launchctl kickstart -k "gui/${uid}/${SERVICE_LABEL}"
  echo "launchd service active: ${SERVICE_LABEL}"
}

write_systemd_unit() {
  run_cmd mkdir -p "${SYSTEMD_USER_DIR}" "${LOG_DIR}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '[dry-run] write %q\n' "${SYSTEMD_UNIT_PATH}"
    return 0
  fi

  cat >"${SYSTEMD_UNIT_PATH}" <<EOF
[Unit]
Description=Voice Backend Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${SCRIPT_DIR}
ExecStart=${BIN_PATH}
Restart=always
RestartSec=2
StandardOutput=append:${LOG_DIR}/out.log
StandardError=append:${LOG_DIR}/err.log

[Install]
WantedBy=default.target
EOF
}

install_systemd_user() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "Error: systemctl not found; cannot install Linux user service." >&2
    exit 1
  fi
  write_systemd_unit
  run_cmd systemctl --user daemon-reload
  run_cmd systemctl --user enable --now "${SYSTEMD_UNIT_NAME}"
  echo "systemd user service active: ${SYSTEMD_UNIT_NAME}"
}

main() {
  ensure_env_file
  build_binary

  case "$(uname -s)" in
    Darwin)
      install_launchd
      ;;
    Linux)
      install_systemd_user
      ;;
    *)
      echo "Error: unsupported OS $(uname -s). Supported: Darwin, Linux." >&2
      exit 1
      ;;
  esac
}

main "$@"
