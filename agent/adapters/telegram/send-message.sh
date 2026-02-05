#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$AGENT_DIR/config/.env"

if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
  echo "Missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID" >&2
  exit 1
fi

MESSAGE="${1:-}"
if [ -z "$MESSAGE" ]; then
  echo "Usage: send-message.sh \"text\"" >&2
  exit 1
fi

curl -fsSL \
  -X POST \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "text=${MESSAGE}" \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
