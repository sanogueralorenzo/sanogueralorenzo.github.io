#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ -f .env ]; then
  mode=$(stat -f %Lp .env 2>/dev/null || stat -c %a .env)
  if [ "$mode" != 600 ]; then
    echo 'Set .env permissions to 600 before starting Slack Reply.' >&2
    exit 1
  fi
  set -a
  . ./.env
  set +a
fi
exec python3 slack_reply.py "$@"
