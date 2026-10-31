#!/bin/sh
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
export PYTHONPATH="$project_root/src"
exec .venv/bin/python -m unittest discover -s tests -p 'test_*.py' "$@"
