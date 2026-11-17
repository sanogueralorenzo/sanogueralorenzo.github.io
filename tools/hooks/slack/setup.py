"""Configure Slack providers and report hook status."""

import json
from pathlib import Path
import shutil
import subprocess
import sys

from service import health


def validate(home, binary):
    result = subprocess.run(
        [str(binary), "config", "--home", str(home)], capture_output=True, text=True
    )
    if result.returncode:
        raise ValueError(
            result.stderr.strip()
            or "Invalid Slack configuration. Edit config.json and run browser-hooks install."
        )
    return json.loads(result.stdout)["hooks"]["slack"]["keywords"]


def configure(home, checkout, workspace, binary):
    path = home / "hooks/slack/config.json"
    if not path.exists():
        commands = {}
        for keyword, agent in [("chat", "codex"), ("claude", "claude")]:
            if shutil.which(agent):
                wrapper = str(checkout / "agents" / f"{agent}.py")
                commands[keyword] = {
                    "start": [sys.executable, wrapper],
                    "resume": [sys.executable, wrapper, "{session_id}"],
                }
        if not commands:
            raise ValueError(
                "Install and sign in to Codex or Claude first, then run browser-hooks install."
            )
        workspace = workspace.expanduser().resolve()
        if not workspace.is_dir():
            raise ValueError(
                "Choose an existing directory with --workspace /path/to/project."
            )
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with path.open("x") as file:
            json.dump(
                {
                    "workspace": str(workspace),
                    "projects": {},
                    "commands": commands,
                },
                file,
                indent=2,
            )
            file.write("\n")
        path.chmod(0o600)
    return validate(home, binary)


def status(home):
    binary = home / "bin/browser-hooks-bridge"
    if not binary.is_file():
        raise ValueError("Rust bridge is missing. Run browser-hooks install.")
    keywords = validate(home, binary)
    folder = home / "hooks/slack"
    result = health()
    print(
        "Browser Hooks bridge (Rust): "
        + ("running" if result else "not running; run browser-hooks install")
    )
    print(
        "Browser: "
        + (
            "paired"
            if result and result["paired"]
            else "not paired; run browser-hooks install, then reload the extension"
        )
    )
    print("Keywords: " + " / ".join(keywords))
    print(f"Configuration: {folder / 'config.json'}")
    print(f"Logs: {home / 'logs/bridge.log'}")
    print(f"Extension folder: {home / 'extension'}")
    config = json.loads((folder / "config.json").read_text())
    for name in ["codex", "claude"]:
        if any(
            Path(arg).name == f"{name}.py"
            for entry in config["commands"].values()
            for arg in entry["start"]
        ):
            print(
                name
                + ": "
                + (
                    "installed (login checked when a request runs)"
                    if shutil.which(name)
                    else "not found; install the CLI and run browser-hooks install"
                )
            )
    if result and result["hooks"]["slack"].get("error"):
        print("Last request: " + result["hooks"]["slack"]["error"]["message"])
    return 0 if result and result["paired"] else 1
