# Config

Local configuration lives here. Keep real secrets in `config/.env` and never
commit that file. Store sanitized examples in `config/example.env`.

## Example

`config/example.env`

```bash
TELEGRAM_BOT_TOKEN=example-token
TELEGRAM_CHAT_ID=123456789
```

## Conventions

- Use `.env` for local secrets (ignored by git).
- Prefer explicit names that map to adapter needs.
