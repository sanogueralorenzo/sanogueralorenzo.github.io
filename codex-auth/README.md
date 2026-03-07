# Codex Auth

Most AI tools still don’t support native multi-account workflows. Separating personal and work/enterprise accounts helps prevent accidental misuse, incorrect metrics and privacy standards.

A local auth profile manager for Codex:
- CLI: `codex-auth`

It manages `~/.codex/auth.json` with secure profile storage in:
- `~/.codex/auth/profiles`

## Build

```bash
cd /path/to/codex-auth
swift build
```

Binaries are generated in:

```bash
cd /path/to/codex-auth
swift build --show-bin-path
```

Then run:
- `$(swift build --show-bin-path)/codex-auth`

## Install helpers

```bash
# Install CLI to your npm global bin
/path/to/codex-auth/scripts/install.sh
```

## CLI usage

```bash
# Save from current ~/.codex/auth.json
codex-auth save personal
codex-auth save work

# Save from an explicit auth.json path
codex-auth save work --path /absolute/path/work-auth.json

# See available profiles
codex-auth list

# Show which profile is currently active
codex-auth current

# Apply a saved profile to ~/.codex/auth.json
codex-auth use work

# Apply directly from a path
codex-auth use --path /absolute/path/work-auth.json

# Remove a saved profile
codex-auth remove personal

# Start auth sync watcher (for menu integrations)
codex-auth watch start
```

Optional (for testing/sandboxed runs):

```bash
codex-auth --home /tmp/demo-home list
```

## Safety behavior

- Validates auth JSON structure before save/use.
- Requires a valid current token at `~/.codex/auth.json` before any profile save.
- Rejects creating a new profile if another saved profile already uses the same `account_id`.
- Uses a lock file (`~/.codex/auth.json.lock`) during writes.
- Uses restrictive filesystem permissions for stored auth files.
- On `use`, automatically invalidates active Codex app and CLI sessions so new credentials are enforced immediately.
- Watcher (`codex-auth watch run`) auto-syncs the active profile only when `~/.codex/auth.json` keeps the same `account_id` (for example token refresh on the same account).

## Notes

- Keep token files private; do not commit them.
