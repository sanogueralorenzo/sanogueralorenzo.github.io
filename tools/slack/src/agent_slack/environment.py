"""Read literal KEY=value configuration without executing shell code."""

import re
import shlex
from pathlib import Path


def read_env(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    if path.stat().st_mode & 0o777 != 0o600:
        raise ValueError(f"Set {path} permissions to 600 before starting Agent Slack")
    values = {}
    for assignment in shlex.split(path.read_text(), comments=True):
        key, separator, value = assignment.partition("=")
        if not separator or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
            raise ValueError("Use KEY=value assignments in .env")
        values[key] = value
    return values
