#!/bin/sh
set -eu
minutes_support="${MINUTES_SUPPORT:-$HOME/Library/Application Support/Minutes}"
mkdir -p "$minutes_support"
chmod 700 "$minutes_support"
python_bin=${PYTHON:-python3}
"$python_bin" -m venv "$minutes_support/runtime"
"$minutes_support/runtime/bin/python3" -m pip install --disable-pip-version-check 'moonshine-voice==0.1.5'
"$minutes_support/runtime/bin/python3" - "$minutes_support/moonshine.json" <<'PY'
import json, sys
from pathlib import Path
from moonshine_voice import get_model_for_language, ModelArch
path, arch = get_model_for_language('en', ModelArch.BASE)
Path(sys.argv[1]).write_text(json.dumps({'path': str(path), 'arch': int(arch)}))
print('Moonshine English model ready. Recordings and transcripts stay on this Mac during transcription.')
PY
