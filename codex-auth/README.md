# Codex Auth

Most AI tools still don’t support native multi-account workflows. Separating personal and work/enterprise accounts helps prevent accidental misuse, incorrect metrics and privacy standards.

A local auth profile manager for Codex:
- CLI: `codex-auth`
- Menu bar app (macOS only): `CodexAuthMenuBar`

It manages `~/.codex/auth.json` with secure profile storage in:
- `~/.codex/auth/profiles`

## Build

```bash
cd /path/to/codex-auth
swift build
```

Binaries are generated at:
- `/path/to/codex-auth/.build/arm64-apple-macosx/debug/codex-auth`
- `/path/to/codex-auth/.build/arm64-apple-macosx/debug/CodexAuthMenuBar` (macOS only)

## Install helpers

```bash
# Install CLI to ~/.local/bin/codex-auth
/path/to/codex-auth/scripts/install.sh

# Build a standalone menu bar .app bundle (macOS only)
/path/to/codex-auth/scripts/package-menubar-app.sh
open /path/to/codex-auth/release/CodexAuthMenuBar.app
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
```

Optional (for testing/sandboxed runs):

```bash
codex-auth --home /tmp/demo-home list
```

## Menu bar app

macOS only.

Run it:

```bash
/path/to/codex-auth/.build/arm64-apple-macosx/debug/CodexAuthMenuBar
```

On first launch, the app writes a user LaunchAgent at
`~/Library/LaunchAgents/io.github.sanogueralorenzo.codexauth.menubar.plist`
so it starts automatically on next login (first launch is manual once).

Menu actions:
- Add
- Use any saved profile
- Remove
- Help
- Quit

## Safety behavior

- Validates auth JSON structure before save/use.
- Requires a valid current token at `~/.codex/auth.json` before any profile save.
- Rejects creating a new profile if its token payload matches an existing saved profile.
- Uses a lock file (`~/.codex/auth.json.lock`) during writes.
- Uses restrictive filesystem permissions for stored auth files.
- On `use`, automatically invalidates active Codex app and CLI sessions so new credentials are enforced immediately.

## Notes

- Keep token files private; do not commit them.
