"""Atomic writes for meeting files and checkpoints."""
import os
from pathlib import Path


def atomic(path, value):
    path = Path(path)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w") as f:
        f.write(value)
        f.flush()
        os.fsync(f.fileno())
    tmp.replace(path)

