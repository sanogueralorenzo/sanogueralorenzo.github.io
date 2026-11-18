"""Explicitly start and stop the shared bridge; never register automatic startup."""

from contextlib import contextmanager
import fcntl
from http.client import HTTPConnection, HTTPException
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

PORT = 19736
LABEL = "dev.browser-hooks.bridge"


def command(home):
    return [
        str(home / "bin/browser-hooks-bridge"), "serve", "--home", str(home),
        "--port", str(PORT),
    ]


def health():
    connection = HTTPConnection("127.0.0.1", PORT, timeout=1)
    try:
        connection.request("GET", "/health")
        response = connection.getresponse()
        value = json.loads(response.read())
        return (
            value
            if response.status == 200
            and isinstance(value, dict)
            and value.get("service") == "browser-hooks"
            and value.get("implementation") == "rust"
            else None
        )
    except (OSError, ValueError, HTTPException):
        return None
    finally:
        connection.close()


@contextmanager
def control(home):
    with (home / "bridge.lock").open("a", encoding="utf-8") as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def running(home):
    path = home / "bridge.pid"
    if not path.exists():
        return None
    try:
        pid = int(path.read_text().strip())
        if pid <= 1:
            raise ValueError()
    except ValueError:
        raise ValueError(f"Invalid process record: {path}") from None
    # Never signal an unrelated process if a stale PID has been reused.
    result = subprocess.run(
        ["ps", "-ww", "-p", str(pid), "-o", "args="], capture_output=True, text=True
    )
    if result.returncode == 0 and result.stdout.strip() == " ".join(command(home)).strip():
        return pid
    return None


def start(home):
    binary = home / "bin/browser-hooks-bridge"
    if not binary.is_file() or not (home / "hooks/slack/config.json").is_file():
        raise ValueError("Browser Hooks is not set up. Run browser-hooks setup.")
    with control(home):
        if running(home):
            print("Browser Hooks is already running. Run browser-hooks status for details.")
            return
        if health():
            raise RuntimeError(
                f"Another bridge is using port {PORT}. Stop it before starting this one."
            )
        logs = home / "logs"
        logs.mkdir(parents=True, exist_ok=True, mode=0o700)
        logs.chmod(0o700)
        log = logs / "bridge.log"
        with log.open("a") as output:
            log.chmod(0o600)
            process = subprocess.Popen(
                command(home), cwd=home, stdin=subprocess.DEVNULL,
                stdout=output, stderr=subprocess.STDOUT, start_new_session=True,
            )
        record = home / "bridge.pid"
        try:
            record.write_text(str(process.pid) + "\n")
            record.chmod(0o600)
            deadline = time.monotonic() + 8
            while process.poll() is None and time.monotonic() < deadline:
                result = health()
                if result and result.get("pid") == process.pid:
                    print("Browser Hooks started. Run browser-hooks stop to turn it off.")
                    return
                time.sleep(0.1)
            raise RuntimeError(f"Bridge did not start. Check {log}; run browser-hooks status.")
        except BaseException:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=10)
            record.unlink(missing_ok=True)
            raise


def stop(home):
    if not home.is_dir():
        print("Browser Hooks is stopped.")
        return
    with control(home):
        pid = running(home)
        if pid:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            deadline = time.monotonic() + 10
            while running(home):
                if time.monotonic() >= deadline:
                    raise RuntimeError("Bridge is still stopping. Check its log, then run browser-hooks stop again.")
                time.sleep(0.1)
        (home / "bridge.pid").unlink(missing_ok=True)
        print("Browser Hooks is stopped.")


def remove_autostart():
    """Remove the replaced login service during setup without enabling anything."""
    if sys.platform == "darwin":
        path = Path.home() / "Library/LaunchAgents" / f"{LABEL}.plist"
        if not path.exists():
            return
        target = f"gui/{os.getuid()}/{LABEL}"
        if subprocess.run(["launchctl", "print", target], capture_output=True).returncode == 0:
            subprocess.run(
                ["launchctl", "bootout", target], capture_output=True, check=True
            )
            deadline = time.monotonic() + 10
            while subprocess.run(["launchctl", "print", target], capture_output=True).returncode == 0:
                if time.monotonic() >= deadline:
                    raise RuntimeError("Previous login service is still stopping. Rerun browser-hooks setup.")
                time.sleep(0.1)
        path.unlink()
    elif sys.platform == "linux":
        path = Path.home() / ".config/systemd/user" / f"{LABEL}.service"
        if not path.exists():
            return
        subprocess.run(
            ["systemctl", "--user", "disable", "--now", f"{LABEL}.service"],
            capture_output=True, check=True,
        )
        path.unlink()
        subprocess.run(
            ["systemctl", "--user", "daemon-reload"], capture_output=True, check=True
        )
    else:
        raise ValueError("Browser Hooks supports macOS and Linux")
