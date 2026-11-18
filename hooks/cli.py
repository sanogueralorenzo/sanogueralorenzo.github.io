#!/usr/bin/env python3
"""Set up and manually control Browser Hooks."""

import argparse
import os
from pathlib import Path
import subprocess
import sys

from paths import app_home


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    shared = argparse.ArgumentParser(add_help=False)
    shared.add_argument("--home", type=Path, default=app_home(), help="Private Browser Hooks directory")
    setup = commands.add_parser("setup", parents=[shared], help="Install/configure without starting")
    setup.add_argument("--workspace", type=Path, default=Path.cwd())
    commands.add_parser("start", parents=[shared], help="Start the bridge in the background")
    commands.add_parser("stop", parents=[shared], help="Stop the bridge and active requests")
    commands.add_parser("status", parents=[shared], help="Show bridge and hook status")
    args = parser.parse_args()
    os.umask(0o077)
    home = args.home.expanduser().resolve()
    checkout = Path(__file__).resolve().parent
    if (
        home.is_relative_to(checkout.parent)
        or checkout.is_relative_to(home / "extension")
        or checkout.is_relative_to(home / "hooks")
    ):
        raise ValueError("Keep private Browser Hooks files outside the public repository")
    if args.command == "setup":
        from installation import setup

        setup(home, checkout, args.workspace)
    elif args.command == "status":
        from slack.setup import status

        raise SystemExit(status(home))
    else:
        from service import start, stop

        (start if args.command == "start" else stop)(home)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"Browser Hooks: {error}", file=sys.stderr)
        raise SystemExit(1)
