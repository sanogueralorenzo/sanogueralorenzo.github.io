import contextlib
from concurrent.futures import ThreadPoolExecutor
import io
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import service
from support import bridge_binary, configuration


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hooks-manual-")
        self.home = Path(self.temp.name).resolve() / "app with spaces"
        self.home.mkdir()
        folder = self.home / "hooks/slack"
        folder.mkdir(parents=True)
        (folder / "config.json").write_text(json.dumps(configuration(self.home)))
        binary = self.home / "bin/browser-hooks-bridge"
        binary.parent.mkdir()
        binary.symlink_to(bridge_binary())
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        self.port = patch("service.PORT", port)
        self.port.start()
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.children = []
        popen = subprocess.Popen

        def track(*args, **kwargs):
            child = popen(*args, **kwargs)
            # subprocess.run also uses Popen; retain only bridge launches.
            if kwargs.get("start_new_session"):
                self.children.append(child)
            return child

        self.spawn = patch("service.subprocess.Popen", side_effect=track)
        self.spawn.start()

    def tearDown(self):
        try:
            service.stop(self.home)
        finally:
            for child in self.children:
                if child.poll() is None:
                    child.terminate()
                child.wait(timeout=10)
            self.spawn.stop()
            self.output.__exit__(None, None, None)
            self.port.stop()
            self.temp.cleanup()

    def test_start_is_idempotent_stop_is_graceful_and_sessions_survive(self):
        config = (self.home / "hooks/slack/config.json").read_bytes()
        service.start(self.home)
        pid = service.running(self.home)
        self.assertIsNotNone(pid)
        self.assertEqual(service.health()["pid"], pid)
        self.assertEqual((self.home / "bridge.pid").stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.home / "logs/bridge.log").stat().st_mode & 0o777, 0o600)
        service.start(self.home)
        self.assertEqual(service.running(self.home), pid)
        self.assertEqual(len(self.children), 1)
        database = self.home / "hooks/slack/sessions.sqlite3"
        self.assertTrue(database.is_file())
        service.stop(self.home)
        self.children[0].wait(timeout=5)
        self.assertIsNone(service.health())
        self.assertFalse((self.home / "bridge.pid").exists())
        self.assertFalse((self.home / "extension/bridge-pairing.json").exists())
        self.assertTrue(database.is_file())
        self.assertEqual((self.home / "hooks/slack/config.json").read_bytes(), config)
        service.stop(self.home)
        service.start(self.home)
        self.assertIsNotNone(service.running(self.home))
        self.assertEqual(len(self.children), 2)

    def test_stale_pid_cannot_signal_an_unrelated_process(self):
        record = self.home / "bridge.pid"
        record.write_text(str(os.getpid()))
        with patch("service.os.kill") as kill:
            service.stop(self.home)
        kill.assert_not_called()
        self.assertFalse(record.exists())
        record.write_text(str(os.getpid()))
        service.start(self.home)
        self.assertNotEqual(service.running(self.home), os.getpid())

    def test_simultaneous_starts_launch_only_one_bridge(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = [pool.submit(service.start, self.home) for _ in range(2)]
            for result in results:
                result.result(timeout=15)
        self.assertEqual(len(self.children), 1)
        self.assertEqual(service.running(self.home), self.children[0].pid)

    def test_cli_start_exits_while_bridge_runs_until_cli_stop(self):
        root = Path(__file__).resolve().parents[2]
        code = (
            "import sys; sys.path.insert(0, sys.argv.pop(1)); "
            "import service; service.PORT=int(sys.argv.pop(1)); "
            "from cli import main; main()"
        )
        def invoke(action):
            return subprocess.run(
                [sys.executable, "-c", code, str(root), str(service.PORT), action,
                 "--home", str(self.home)],
                capture_output=True, text=True, timeout=15,
            )
        result = invoke("start")
        self.assertEqual(result.returncode, 0, result.stderr)
        pid = service.running(self.home)
        self.assertIsNotNone(pid)
        self.assertEqual(os.getpgid(pid), pid)
        result = invoke("status")
        self.assertIn("bridge (Rust): running", result.stdout)
        result = invoke("start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(service.running(self.home), pid)
        result = invoke("stop")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(service.running(self.home))
        self.assertIsNone(service.health())

    def test_crash_is_not_restarted_and_next_start_recovers_stale_pid(self):
        service.start(self.home)
        child = self.children[0]
        child.kill()
        child.wait(timeout=5)
        self.assertIsNone(service.running(self.home))
        self.assertIsNone(service.health())
        self.assertEqual(len(self.children), 1)
        service.start(self.home)
        self.assertNotEqual(service.running(self.home), child.pid)

    def test_failed_start_reports_log_and_cleans_process_record(self):
        binary = self.home / "bin/browser-hooks-bridge"
        binary.unlink()
        binary.write_text("#!/bin/sh\necho synthetic-startup-failure >&2\nexit 1\n")
        binary.chmod(0o700)
        with self.assertRaisesRegex(RuntimeError, "Bridge did not start.*bridge.log"):
            service.start(self.home)
        self.assertFalse((self.home / "bridge.pid").exists())
        self.assertIn("synthetic-startup-failure", (self.home / "logs/bridge.log").read_text())

    def test_other_bridge_is_never_adopted_or_stopped(self):
        with patch("service.health", return_value={"pid": 123}):
            with self.assertRaisesRegex(RuntimeError, "Another bridge"):
                service.start(self.home)
        self.assertEqual(self.children, [])

    def test_start_before_setup_and_stop_before_setup(self):
        missing = self.home / "missing"
        with self.assertRaisesRegex(ValueError, "browser-hooks setup"):
            service.start(missing)
        service.stop(missing)
        self.assertFalse(missing.exists())


class AutostartRemovalTests(unittest.TestCase):
    def test_macos_setup_unloads_and_deletes_previous_login_service(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / "Library/LaunchAgents" / f"{service.LABEL}.plist"
            path.parent.mkdir(parents=True)
            path.write_bytes(b"existing plist")
            with (
                patch("service.sys.platform", "darwin"),
                patch("service.Path.home", return_value=root),
                patch("service.subprocess.run", side_effect=[Mock(returncode=0), Mock(returncode=0), Mock(returncode=1)]) as run,
            ):
                service.remove_autostart()
                service.remove_autostart()
            self.assertFalse(path.exists())
            self.assertEqual([c.args[0][1] for c in run.call_args_list], ["print", "bootout", "print"])

    def test_linux_setup_disables_and_removes_previous_service(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / ".config/systemd/user" / f"{service.LABEL}.service"
            path.parent.mkdir(parents=True)
            path.write_bytes(b"existing unit")
            with (
                patch("service.sys.platform", "linux"),
                patch("service.Path.home", return_value=root),
                patch("service.subprocess.run", return_value=Mock(returncode=0)) as run,
            ):
                service.remove_autostart()
                service.remove_autostart()
            self.assertFalse(path.exists())
            self.assertEqual([c.args[0][2:] for c in run.call_args_list], [["disable", "--now", f"{service.LABEL}.service"], ["daemon-reload"]])

    def test_failed_unload_keeps_service_file(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / "Library/LaunchAgents" / f"{service.LABEL}.plist"
            path.parent.mkdir(parents=True)
            path.write_bytes(b"existing plist")
            with (
                patch("service.sys.platform", "darwin"),
                patch("service.Path.home", return_value=root),
                patch("service.subprocess.run", side_effect=[Mock(returncode=0), subprocess.CalledProcessError(1, ["launchctl", "bootout"])]),
                self.assertRaises(subprocess.CalledProcessError),
            ):
                service.remove_autostart()
            self.assertTrue(path.exists())
