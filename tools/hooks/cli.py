#!/usr/bin/env python3
"""Install and inspect Browser Hooks and its website adapters."""

import argparse
import os
from pathlib import Path
import sys

from paths import app_home


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    shared = argparse.ArgumentParser(add_help=False)
    shared.add_argument(
        "--home", type=Path, default=app_home(), help="Private Browser Hooks directory"
    )
    install = commands.add_parser(
        "install", parents=[shared], help="Install the extension and available hooks"
    )
    install.add_argument("--workspace", type=Path, default=Path.cwd())
    commands.add_parser("status", parents=[shared], help="Show hook status")
    slack = commands.add_parser("slack", help="Slack hook")
    actions = slack.add_subparsers(dest="action", required=True)
    actions.add_parser("status", parents=[shared], help="Show Slack status")
    actions.add_parser("serve", parents=[shared], help="Run the local Slack bridge")
    args = parser.parse_args()
    os.umask(0o077)
    home = args.home.expanduser().resolve()
    checkout = Path(__file__).resolve().parent
    if (
        home.is_relative_to(checkout.parents[1])
        or checkout.is_relative_to(home / "extension")
        or checkout.is_relative_to(home / "hooks")
    ):
        raise ValueError(
            "Keep private Browser Hooks files outside the public repository"
        )
    if args.command == "install":
        from installation import install

        install(home, checkout, args.workspace)
    elif args.command == "status" or args.action == "status":
        from slack.setup import status

        raise SystemExit(status(home))
    else:
        binary = home / "bin/slack-bridge"
        if not binary.is_file():
            raise ValueError("Rust bridge is missing. Run browser-hooks install.")
        os.execv(binary, [str(binary), "serve", "--home", str(home)])


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(f"Browser Hooks: {error}", file=sys.stderr)
        raise SystemExit(1)
