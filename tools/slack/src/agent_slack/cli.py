"""Run the configured Slack bridge."""

import argparse
import os
import sys
from pathlib import Path

from .app import Application, Config
from .environment import read_env


def run(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path(".env"), help="configuration file (default: .env)")
    args = parser.parse_args(argv)
    path = args.config.expanduser().resolve()
    for key, value in read_env(path).items():
        os.environ.setdefault(key, value)
    if path.exists():
        os.chdir(path.parent)
    Application(Config.from_env()).run()


def main():
    try:
        run()
    except KeyboardInterrupt:
        pass
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Agent Slack: {error}", file=sys.stderr)
        return 1
