"""Prepare the shared extension and command launcher."""

from pathlib import Path
import shlex
import sys

from extension import prepare
from build import build
from service import start
from slack.setup import configure


def launcher(home, checkout):
    target = Path.home() / ".local/bin/browser-hooks"
    target.parent.mkdir(parents=True, exist_ok=True)
    command = " ".join(
        shlex.quote(str(arg)) for arg in [sys.executable, checkout / "cli.py"]
    )
    target.write_text(
        "#!/bin/sh\nexport BROWSER_HOOKS_HOME="
        + shlex.quote(str(home))
        + "\nexec "
        + command
        + ' "$@"\n'
    )
    target.chmod(0o700)
    return target


def install(home, checkout, workspace):
    binary = build(home, checkout)
    keywords = configure(home, checkout / "slack", workspace, binary)
    extension = prepare(checkout, home)
    start(home, binary)
    executable = launcher(home, checkout)
    print("Slack is ready. Keywords: " + " / ".join(keywords))
    print(f"Configuration: {home / 'hooks/slack/config.json'}")
    print("Slack attaches automatically. Keep one Slack tab open; no listening toggle.")
    print(f"Extension folder: {extension}")
    print("Load this folder unpacked in Edge/Chrome (Developer mode → Load unpacked).")
    print(
        "Pairing happens automatically; no code to copy. Load or reload within ten minutes."
    )
    print("After updates, reload Browser Hooks once, then reload Slack.")
    print(f"Check all hooks: {executable} status")
