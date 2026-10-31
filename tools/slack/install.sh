#!/bin/sh
set -eu
umask 077

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) echo 'Agent Slack installation supports macOS and Linux.' >&2; exit 1 ;;
esac
command -v git >/dev/null || { echo 'Install Git first.' >&2; exit 1; }
command -v curl >/dev/null || { echo 'Install curl first.' >&2; exit 1; }

checkout_dir=$(mktemp -d "${TMPDIR:-/tmp}/agent-slack-source.XXXXXX")
trap 'rm -rf "$checkout_dir"' EXIT
trap 'exit 1' HUP INT TERM

install_dir="$HOME/.local/share/agent-slack"
mkdir -p "$install_dir"
uv_bin="$install_dir/.runtime/uv"
if [ ! -x "$uv_bin" ]; then
  curl -fsSL https://astral.sh/uv/install.sh -o "$checkout_dir/install-uv.sh"
  UV_UNMANAGED_INSTALL="$install_dir/.runtime" sh "$checkout_dir/install-uv.sh"
fi
export UV_PYTHON_INSTALL_DIR="$install_dir/.runtime/python"
export UV_PYTHON_INSTALL_BIN=false
"$uv_bin" python install 3.12
python_bin=$("$uv_bin" python find --managed-python 3.12)

git clone --quiet --depth 1 --filter=blob:none --sparse --branch main \
  https://github.com/sanogueralorenzo/sanogueralorenzo.github.io.git "$checkout_dir/repo"
git -C "$checkout_dir/repo" sparse-checkout set tools/slack
revision=$(git -C "$checkout_dir/repo" rev-parse --short HEAD)
source_dir="$checkout_dir/repo/tools/slack"

if [ -x "$install_dir/.venv/bin/agent-slack-setup" ]; then
  "$install_dir/.venv/bin/agent-slack-setup" --stop
fi
"$uv_bin" venv --python "$python_bin" --clear "$install_dir/.venv"
"$uv_bin" pip install --python "$install_dir/.venv/bin/python" "$source_dir"

cd "$install_dir"
"$install_dir/.venv/bin/agent-slack-setup" "$revision"
