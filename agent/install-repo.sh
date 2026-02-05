#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"

if [ -z "$REPO_ROOT" ] && [ -d "$PWD/.git" ]; then
  REPO_ROOT="$PWD"
fi

if [ -z "$REPO_ROOT" ]; then
  echo "No git repository found. Run this inside a repo." >&2
  exit 1
fi

GITIGNORE_FILE="$REPO_ROOT/.gitignore"
if [ -f "$GITIGNORE_FILE" ]; then
  if ! grep -qxF "**/.env" "$GITIGNORE_FILE"; then
    printf '\n**/.env\n' >> "$GITIGNORE_FILE"
  fi
else
  printf '**/.env\n' > "$GITIGNORE_FILE"
fi

if [ -d "$REPO_ROOT/.git" ] && [ -f "$SCRIPT_DIR/hooks/pre-commit" ]; then
  install -m 0755 "$SCRIPT_DIR/hooks/pre-commit" "$REPO_ROOT/.git/hooks/pre-commit"
fi

echo "Repo guardrails installed in: $REPO_ROOT"
