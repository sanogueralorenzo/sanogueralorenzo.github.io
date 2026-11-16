"""Install, start, and inspect the shared bridge on macOS or Linux."""

import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import time
from http.client import HTTPConnection, HTTPException

LABEL = "dev.browser-hooks.bridge"


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


def start(home, binary):
    install(binary, home)
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if health():
            return
        time.sleep(0.1)
    raise RuntimeError(
        f"Bridge did not start. Run browser-hooks status; check {home / 'logs/bridge.log'}."
    )


def specification(binary, home):
    return {
        "Label": LABEL,
        "ProgramArguments": [str(binary), "serve", "--home", str(home)],
        "RunAtLoad": True,
        "KeepAlive": True,
        "WorkingDirectory": str(home),
        "EnvironmentVariables": {"PATH": os.environ.get("PATH", "/usr/bin:/bin")},
        "StandardOutPath": str(home / "logs/bridge.log"),
        "StandardErrorPath": str(home / "logs/bridge.log"),
        "Umask": 0o077,
        "ThrottleInterval": 10,
    }


def install(binary, home):
    if sys.platform not in ("darwin", "linux"):
        raise ValueError("Installation supports macOS and Linux")
    logs = home / "logs"
    logs.mkdir(parents=True, exist_ok=True, mode=0o700)
    logs.chmod(0o700)
    log = home / "logs/bridge.log"
    log.touch(mode=0o600, exist_ok=True)
    log.chmod(0o600)
    if sys.platform == "linux":
        install_linux(binary, home)
    else:
        install_macos(binary, home)
    print(f"Installed {LABEL}; starts automatically at login.")


def install_macos(binary, home):
    folder = Path.home() / "Library" / "LaunchAgents"
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{LABEL}.plist"
    target = f"gui/{os.getuid()}/{LABEL}"
    loaded = (
        subprocess.run(["launchctl", "print", target], capture_output=True).returncode
        == 0
    )
    if loaded:
        result = subprocess.run(["launchctl", "bootout", target], capture_output=True)
        if result.returncode:
            raise RuntimeError(
                "Could not stop the previous bridge service. Check launchctl for "
                + LABEL
            )
    path.write_bytes(plistlib.dumps(specification(binary, home)))
    path.chmod(0o600)
    deadline = time.monotonic() + 5
    while True:
        result = subprocess.run(
            ["launchctl", "bootstrap", f"gui/{os.getuid()}", str(path)],
            capture_output=True,
        )
        if not result.returncode:
            break
        # launchd can return EIO briefly while a booted-out job finishes exiting.
        if not loaded or result.returncode != 5 or time.monotonic() >= deadline:
            raise RuntimeError(
                f"Could not start bridge service (launchctl exit {result.returncode}). Check the private bridge log."
            )
        time.sleep(0.2)


def unit_value(value):
    return (
        '"'
        + str(value)
        .replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("%", "%%")
        + '"'
    )


def linux_unit(binary, home):
    args = specification(binary, home)["ProgramArguments"]
    return (
        "[Unit]\nDescription=Browser Hooks bridge\n\n[Service]\n"
        + "ExecStart="
        + " ".join(unit_value(arg) for arg in args)
        + "\n"
        + "WorkingDirectory="
        + unit_value(home)
        + "\n"
        + "Environment="
        + unit_value("PATH=" + os.environ.get("PATH", os.defpath))
        + "\n"
        + "UMask=0077\nRestart=on-failure\nRestartSec=10\nKillMode=mixed\nTimeoutStopSec=10\n"
        + "StandardOutput="
        + unit_value("append:" + str(home / "logs/bridge.log"))
        + "\n"
        + "StandardError="
        + unit_value("append:" + str(home / "logs/bridge.log"))
        + "\n\n[Install]\nWantedBy=default.target\n"
    )


def install_linux(binary, home):
    path = Path.home() / ".config" / "systemd/user" / f"{LABEL}.service"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(linux_unit(binary, home))
    path.chmod(0o600)
    for args in [
        ["daemon-reload"],
        ["enable", f"{LABEL}.service"],
        ["restart", f"{LABEL}.service"],
    ]:
        result = subprocess.run(["systemctl", "--user", *args], capture_output=True)
        if result.returncode:
            raise RuntimeError(
                "Could not start the user service. Check systemctl --user status "
                + LABEL
            )
