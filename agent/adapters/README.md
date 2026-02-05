# Adapters

Adapters wrap external systems so actions can reuse them without duplicating
curl flags, auth headers, or response parsing.

## Suggested layout

```
adapters/
  telegram/
    send-message.sh
  github/
    list-repos.sh
```

## Example adapter

`adapters/telegram/send-message.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

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
```

## Conventions

- Read secrets from `config/.env`.
- Keep adapters focused on I/O, not workflow logic.
