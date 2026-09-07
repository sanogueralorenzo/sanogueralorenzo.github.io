#!/bin/sh
set -eu

if [ "$(uname -s)" != Darwin ]; then
  echo "Rewrite requires macOS 14 or later." >&2
  exit 1
fi
xcrun --find swiftc >/dev/null

checkout_dir=$(mktemp -d "${TMPDIR:-/tmp}/rewrite-source.XXXXXX")
install_stage=
cleanup() {
  result=$?
  rm -rf "$checkout_dir"
  if [ -n "$install_stage" ]; then
    if [ "$result" -eq 0 ] || [ ! -d "$install_stage/previous.app" ]; then
      rm -rf "$install_stage"
    else
      echo "Previous app preserved at $install_stage/previous.app" >&2
    fi
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

case "${1:-}" in
  --local)
    source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
    revision="local checkout"
    ;;
  "")
    git clone --quiet --depth 1 --filter=blob:none --sparse --branch main \
      https://github.com/sanogueralorenzo/sanogueralorenzo.github.io.git "$checkout_dir/repo"
    git -C "$checkout_dir/repo" sparse-checkout set tools/rewrite
    revision=$(git -C "$checkout_dir/repo" rev-parse --short HEAD)
    source_dir="$checkout_dir/repo/tools/rewrite"
    ;;
  *) echo "Usage: install.sh [--local]" >&2; exit 1 ;;
esac
"$source_dir/build.sh"

mkdir -p "$HOME/Applications"
installed_app="$HOME/Applications/Rewrite.app"
install_stage=$(mktemp -d "$HOME/Applications/.rewrite-install.XXXXXX")
ditto "$source_dir/build/Rewrite.app" "$install_stage/new.app"
codesign --verify --deep --strict "$install_stage/new.app"

pkill -TERM -x Rewrite 2>/dev/null || true
attempts=0
while pgrep -x Rewrite >/dev/null; do
  attempts=$((attempts + 1))
  if [ "$attempts" -ge 50 ]; then
    echo "Rewrite did not quit; the installed app has not been replaced." >&2
    exit 1
  fi
  sleep 0.1
done

if [ -d "$installed_app" ]; then mv "$installed_app" "$install_stage/previous.app"; fi
if ! mv "$install_stage/new.app" "$installed_app"; then
  if [ -d "$install_stage/previous.app" ]; then mv "$install_stage/previous.app" "$installed_app"; fi
  exit 1
fi
open "$installed_app"
echo "Installed Rewrite ($revision) at $installed_app"
