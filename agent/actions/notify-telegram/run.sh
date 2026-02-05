#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAPTER="$SCRIPT_DIR/../../adapters/telegram/send-message.sh"

if [ ! -x "$ADAPTER" ]; then
  echo "Missing adapter: $ADAPTER" >&2
  exit 1
fi

MESSAGE="${1:-}"
if [ -z "$MESSAGE" ]; then
  echo "Usage: run.sh \"message\"" >&2
  exit 1
fi

"$ADAPTER" "$MESSAGE"
