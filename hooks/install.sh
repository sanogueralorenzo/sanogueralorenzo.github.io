#!/bin/sh
set -eu
umask 077

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) echo "Installation supports macOS and Linux." >&2; exit 1 ;;
esac

command -v git >/dev/null || { echo 'Install Git first, then rerun this installer.' >&2; exit 1; }
python_bin=''
for candidate in python3 python3.15 python3.14 python3.13 python3.12 python3.11; do
  if command -v "$candidate" >/dev/null && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
    python_bin=$(command -v "$candidate")
    break
  fi
done
[ -n "$python_bin" ] || { echo 'Install Python 3.11 or newer, then rerun this installer.' >&2; exit 1; }

command -v cargo >/dev/null || { echo 'Install Rust/Cargo and a C compiler first, then rerun this installer.' >&2; exit 1; }

install_dir="${BROWSER_HOOKS_HOME:-$HOME/.local/share/browser-hooks}"
case "$install_dir" in
  /*) ;;
  *) echo 'BROWSER_HOOKS_HOME must be an absolute path.' >&2; exit 1 ;;
esac
source_dir="$install_dir/source"
if [ -d "$source_dir/.git" ]; then
  [ -z "$(git -C "$source_dir" status --porcelain)" ] || { echo "Local edits in $source_dir; save them before updating." >&2; exit 1; }
  git -C "$source_dir" pull --quiet --ff-only origin main
else
  mkdir -p "$(dirname "$source_dir")"
  git clone --quiet --depth 1 --filter=blob:none --sparse --branch main \
    https://github.com/sanogueralorenzo/sanogueralorenzo.github.io.git "$source_dir"
fi
git -C "$source_dir" sparse-checkout set hooks
"$python_bin" "$source_dir/hooks/cli.py" setup --home "$install_dir" "$@"
