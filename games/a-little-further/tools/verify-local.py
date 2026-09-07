#!/usr/bin/env python3
"""Verify the private runtime package without printing source contents."""
import hashlib
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1] / 'Local'
manifest = root / 'runtime-manifest.json'
if not manifest.exists():
    raise SystemExit('Missing private runtime manifest. Run tools/restore-local.sh.')
expected = json.loads(manifest.read_text())
failures = []
for name, digest in expected.items():
    file = root / name
    if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != digest:
        failures.append(name)
if failures:
    raise SystemExit('Private runtime verification failed: ' + ', '.join(failures))
print(f'Private runtime verified: {len(expected)} files.')
