#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  install.sh [--install|--update|--uninstall] [--prefix DIR]

Environment:
  TRACE_INSTALL_DIR  Install directory when --prefix is not provided.
USAGE
}

action="install"
install_dir="${TRACE_INSTALL_DIR:-$HOME/.local/bin}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      action="install"
      shift
      ;;
    --update)
      action="update"
      shift
      ;;
    --uninstall)
      action="uninstall"
      shift
      ;;
    --prefix)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --prefix\n' >&2
        exit 1
      fi
      install_dir="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$install_dir/trace"
source_bin="$script_dir/bin/trace.mjs"

if [[ "$action" == "uninstall" ]]; then
  if [[ -L "$target" || -f "$target" ]]; then
    rm -f "$target"
    printf 'Uninstalled trace from %s\n' "$target"
  else
    printf 'Trace is not installed at %s\n' "$target"
  fi
  exit 0
fi

if [[ ! -f "$source_bin" ]]; then
  printf 'Trace CLI not found: %s\n' "$source_bin" >&2
  exit 1
fi

mkdir -p "$install_dir"
ln -sf "$source_bin" "$target"

if [[ "$action" == "update" ]]; then
  printf 'Updated trace -> %s\n' "$target"
else
  printf 'Installed trace -> %s\n' "$target"
fi
