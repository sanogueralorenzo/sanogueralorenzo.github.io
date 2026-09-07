#!/bin/sh
set -eu
if [ "$(uname -s)" != Darwin ] || [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 15 ]; then
  echo "Minutes requires macOS 15 or later." >&2
  exit 1
fi
xcrun --find swiftc >/dev/null
python3 -c 'import sys; assert sys.version_info >= (3, 10), "Python 3.10+ is required (brew install python)"'
checkout=$(mktemp -d "${TMPDIR:-/tmp}/minutes-source.XXXXXX")
install_stage=
cleanup() {
  result=$?
  rm -rf "$checkout"
  if [ -n "$install_stage" ]; then
    if [ "$result" -eq 0 ] || [ ! -d "$install_stage/previous.app" ]; then rm -rf "$install_stage";
    else echo "Previous app preserved at $install_stage/previous.app" >&2; fi
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
# Updating while recording could strand a meeting; the app intentionally refuses to quit while busy.
if pgrep -x MinutesHost >/dev/null; then
  echo "Finish the current meeting and quit Minutes before installing or updating." >&2
  exit 1
fi
git clone --quiet --depth 1 --filter=blob:none --sparse --branch main \
  https://github.com/sanogueralorenzo/sanogueralorenzo.github.io.git "$checkout/repo"
git -C "$checkout/repo" sparse-checkout set tools/minutes
minutes_source="$checkout/repo/tools/minutes"
"$minutes_source/build.sh"
"$minutes_source/setup.sh"
mkdir -p "$HOME/Applications"
install_stage=$(mktemp -d "$HOME/Applications/.minutes-install.XXXXXX")
ditto "$minutes_source/build/Minutes.app" "$install_stage/new.app"
codesign --verify --deep --strict "$install_stage/new.app"
installed_app="$HOME/Applications/Minutes.app"
if [ -d "$installed_app" ]; then mv "$installed_app" "$install_stage/previous.app"; fi
if ! mv "$install_stage/new.app" "$installed_app"; then
  if [ -d "$install_stage/previous.app" ]; then mv "$install_stage/previous.app" "$installed_app"; fi
  exit 1
fi
open "$installed_app"
printf 'Installed Minutes at %s\n' "$installed_app"
