"""Configure providers, install the native service, and report its health."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
from http.client import HTTPConnection, HTTPException

from service import install


def health():
    connection = HTTPConnection("127.0.0.1", 19736, timeout=1)
    try:
        connection.request("GET", "/health")
        response = connection.getresponse()
        value = json.loads(response.read())
        return (
            value
            if response.status == 200
            and value.get("service") == "browser-hooks"
            and value.get("implementation") == "rust"
            else None
        )
    except (OSError, ValueError, HTTPException):
        return None
    finally:
        connection.close()


def validate(home, binary):
    result = subprocess.run(
        [str(binary), "config", "--home", str(home)], capture_output=True, text=True
    )
    if result.returncode:
        raise ValueError(
            result.stderr.strip()
            or "Invalid Slack configuration. Edit config.json and rerun the installer."
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
                "Install and sign in to Codex or Claude first, then rerun the installer."
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
                    "timeout_seconds": 600,
                },
                file,
                indent=2,
            )
            file.write("\n")
        path.chmod(0o600)
    return validate(home, binary)


def start(home, binary, keywords):
    install(binary, home)
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if health():
            break
        time.sleep(0.1)
    else:
        raise RuntimeError(
            f"Bridge did not start. Check {home / 'logs/bridge.log'}"
        )
    print("Slack is ready. Keywords: " + " / ".join(keywords))
    print(f"Configuration: {home / 'hooks/slack/config.json'}")
    print("Slack attaches automatically. Keep one Slack tab open; no listening toggle.")


def status(home):
    binary = home / "bin/browser-hooks-bridge"
    if not binary.is_file():
        raise ValueError("Rust bridge is missing. Run browser-hooks install.")
    keywords = validate(home, binary)
    folder = home / "hooks/slack"
    result = health()
    print(
        "Browser Hooks bridge (Rust): "
        + ("running" if result else "not running; rerun the installer")
    )
    print(
        "Browser: "
        + (
            "paired"
            if result and result["paired"]
            else "not paired; rerun the installer, then reload the extension"
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
                    else "not found; install the CLI and rerun the installer"
                )
            )
    if result and result["hooks"]["slack"].get("error"):
        print("Last request: " + result["hooks"]["slack"]["error"]["message"])
    return 0 if result and result["paired"] else 1
