"""Configure the installed package and register its per-user background service."""

import getpass
import json
import os
import platform
import plistlib
import shlex
import shutil
import subprocess
import sys
import webbrowser
from importlib.resources import files
from pathlib import Path
from urllib.parse import urlencode

from .environment import read_env


ROOT = Path.home() / ".local/share/agent-slack"
SERVICE = "dev.sanogueralorenzo.agent-slack"


def service_path(system):
    if system == "Darwin":
        return Path.home() / "Library/LaunchAgents" / f"{SERVICE}.plist"
    if system == "Linux":
        return Path.home() / ".config/systemd/user" / f"{SERVICE}.service"
    raise ValueError("Installation supports macOS and Linux")


def stop_service(system):
    target = service_path(system)
    if not target.exists():
        return
    command = (["launchctl", "bootout", f"gui/{os.getuid()}", str(target)] if system == "Darwin"
               else ["systemctl", "--user", "stop", f"{SERVICE}.service"])
    subprocess.run(command, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def read_config():
    values = {key: os.environ.get(key, value) for key, value in read_env(ROOT / ".env").items()}
    for key in ("SLACK_APP_TOKEN", "SLACK_USER_TOKEN", "SLACK_USER_ID", "AGENT_SLACK_COMMANDS",
                "AGENT_SLACK_WORKSPACE", "AGENT_SLACK_PROJECTS", "AGENT_SLACK_STATE_DIR"):
        if key not in values and key in os.environ:
            values[key] = os.environ[key]
    values.setdefault("AGENT_SLACK_WORKSPACE", str(Path.home()))
    if not values.get("AGENT_SLACK_COMMANDS"):
        commands = {
            keyword: {"start": [str(ROOT / f".venv/bin/agent-slack-{cli}")],
                      "resume": [str(ROOT / f".venv/bin/agent-slack-{cli}"), "{session_id}"]}
            for keyword, cli in (("chat", "codex"), ("claude", "claude")) if shutil.which(cli)
        }
        if not commands:
            raise ValueError("Install and authenticate Codex or Claude first, or set AGENT_SLACK_COMMANDS")
        values["AGENT_SLACK_COMMANDS"] = json.dumps(commands, separators=(",", ":"))
    return values


def save_config(values):
    ROOT.mkdir(parents=True, exist_ok=True)
    path = ROOT / ".env"
    temporary = ROOT / ".env.new"
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as output:
        for key, value in values.items():
            output.write(f"{key}={shlex.quote(value)}\n")
    temporary.chmod(0o600)
    temporary.replace(path)


def ask_token(label):
    # A curl | sh installation still reads secrets from the terminal, never the pipe.
    try:
        with open("/dev/tty", "w") as terminal:
            return getpass.getpass(label, stream=terminal).strip()
    except (OSError, EOFError):
        return ""


def configure(manifest):
    values = read_config()
    if not values.get("SLACK_APP_TOKEN") or not values.get("SLACK_USER_TOKEN"):
        save_config(values)
        url = "https://api.slack.com/apps"
        if not values.get("SLACK_APP_TOKEN"):
            url += "?" + urlencode({"new_app": "1", "manifest_json": json.dumps(manifest, separators=(",", ":"))})
            print("Create your Slack app and request workspace approval if required:")
            print("Create an app-level token with connections:write under Basic Information.")
        else:
            print("Open your existing Slack app. After approval, install it under OAuth & Permissions:")
        print(url)
        print("Copy the User OAuth Token from OAuth & Permissions. No bot token is needed.")
        if platform.system() == "Darwin" or os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"):
            webbrowser.open(url)
        if not values.get("SLACK_APP_TOKEN"):
            values["SLACK_APP_TOKEN"] = ask_token("App-level token (xapp-, Enter to finish later): ")
        if not values["SLACK_APP_TOKEN"]:
            return False
        if not values["SLACK_APP_TOKEN"].startswith("xapp-"):
            raise ValueError("Use an xapp app-level token")
        if not values.get("SLACK_USER_TOKEN"):
            values["SLACK_USER_TOKEN"] = ask_token("User OAuth token (xoxp-, Enter to finish later): ")
        if not values["SLACK_USER_TOKEN"]:
            save_config(values)
            return False
    if not values["SLACK_APP_TOKEN"].startswith("xapp-") or not values["SLACK_USER_TOKEN"].startswith("xoxp-"):
        raise ValueError("Use an xapp app-level token and an xoxp user token")
    from slack_sdk import WebClient
    from slack_sdk.errors import SlackApiError

    try:
        auth = WebClient(token=values["SLACK_USER_TOKEN"]).auth_test()
        WebClient(token=values["SLACK_APP_TOKEN"]).apps_connections_open()
    except SlackApiError as error:
        raise ValueError("Slack authentication: " + error.response.get("error", "failed")) from None
    if auth.get("bot_id"):
        raise ValueError("Use your human user OAuth token")
    if values.get("SLACK_USER_ID") and values["SLACK_USER_ID"] != auth["user_id"]:
        raise ValueError("The user token does not belong to the configured SLACK_USER_ID")
    header = auth.headers.get("x-oauth-scopes", "")
    scopes = set((header if isinstance(header, str) else ",".join(header)).split(","))
    missing = set(manifest["oauth_config"]["scopes"]["user"]) - scopes
    if missing:
        raise ValueError("Approve/reinstall the Slack app with these user scopes: " + ", ".join(sorted(missing)))
    values["SLACK_USER_ID"] = auth["user_id"]
    save_config(values)
    os.environ.update(values)
    from .app import Config

    return Config.from_env()


def unit_value(value):
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r").replace("%", "%%") + '"'


def start_service(system, config):
    target = service_path(system)
    target.parent.mkdir(parents=True, exist_ok=True)
    path = os.environ.get("PATH", os.defpath)
    command = [str(ROOT / ".venv/bin/agent-slack"), "--config", str(ROOT / ".env")]
    if system == "Darwin":
        config.state_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        config.state_dir.chmod(0o700)
        log = config.state_dir / "agent-slack.log"
        log.touch(mode=0o600, exist_ok=True)
        log.chmod(0o600)
        data = {
            "Label": SERVICE, "ProgramArguments": command, "WorkingDirectory": str(ROOT),
            "EnvironmentVariables": {"PATH": path, "HOME": str(Path.home())},
            "RunAtLoad": True, "KeepAlive": {"SuccessfulExit": False}, "ThrottleInterval": 10,
            "StandardOutPath": str(log), "StandardErrorPath": str(log),
        }
        target.write_bytes(plistlib.dumps(data))
        stop_service(system)
        subprocess.run(["launchctl", "bootstrap", f"gui/{os.getuid()}", str(target)], check=True)
        print(f"Logs: {log}")
    else:
        target.write_text(
            "[Unit]\nDescription=Agent Slack\n\n[Service]\n"
            f"ExecStart={' '.join(unit_value(arg) for arg in command)}\nWorkingDirectory={unit_value(ROOT)}\n"
            f"Environment={unit_value('PATH=' + path)}\nEnvironment={unit_value('HOME=' + str(Path.home()))}\n"
            "Restart=on-failure\nRestartSec=10\nKillMode=mixed\nTimeoutStopSec=10\n\n"
            "[Install]\nWantedBy=default.target\n"
        )
        linger = subprocess.run(["loginctl", "enable-linger"], check=False, capture_output=True)
        if linger.returncode:
            print("To keep the service running after logout, ask your administrator to enable user lingering with loginctl enable-linger.")
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
        subprocess.run(["systemctl", "--user", "enable", "--now", f"{SERVICE}.service"], check=True)
        print(f"Logs: journalctl --user -u {SERVICE}.service")
    print(f"Configuration: {ROOT / '.env'}")


def run():
    system = platform.system()
    if sys.argv[1:] == ["--stop"]:
        stop_service(system)
        return
    manifest = json.loads(files("agent_slack").joinpath("manifest.json").read_text())
    config = configure(manifest)
    if not config:
        print(f"Local setup is ready at {ROOT}. Rerun the installer after Slack approval to enter the tokens.")
        return
    start_service(system, config)
    revision = sys.argv[1] if len(sys.argv) == 2 else "local checkout"
    print(f"Agent Slack installed from main ({revision}). Enabled keywords: {'/'.join(config.commands)}.")


def main():
    try:
        run()
    except KeyboardInterrupt:
        print("\nSetup paused. Rerun the installer when ready.", file=sys.stderr)
        return 1
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Agent Slack installation: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
