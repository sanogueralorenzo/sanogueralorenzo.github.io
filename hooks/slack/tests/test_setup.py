import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from installation import setup as setup_hooks, launcher
from paths import app_home
from slack.setup import configure, status, validate
from support import bridge_binary


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.home = self.root / "app"
        self.folder = self.home / "hooks/slack"
        self.path = self.folder / "config.json"
        self.checkout = Path(__file__).resolve().parents[2]
        self.binary = bridge_binary()

    def tearDown(self):
        self.temp.cleanup()

    def configure(self):
        with patch("slack.setup.shutil.which", return_value=sys.executable):
            return configure(self.home, self.checkout / "slack", self.root, self.binary)

    def test_first_install_discovers_both_clis_and_defaults_to_chat_and_claude(self):
        self.assertEqual(set(self.configure()), {"chat", "claude"})
        config = json.loads(self.path.read_text())
        self.assertTrue(
            config["commands"]["chat"]["start"][1].endswith("/slack/agents/codex.py")
        )
        self.assertEqual(config["commands"]["claude"]["resume"][-1], "{session_id}")
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_setup_preserves_config_pairing_and_database_without_starting(
        self,
    ):
        self.configure()
        config = json.loads(self.path.read_text())
        config["commands"]["custom"] = config["commands"].pop("chat")
        config["projects"] = {"demo": str(self.root)}
        self.path.write_text(json.dumps(config))
        files = {
            "config.json": self.path.read_bytes(),
            "sessions.sqlite3": b"existing database bytes",
        }
        pairing = self.home / "pairing.json"
        pairing.write_bytes(b"synthetic-saved-key")
        for name, data in files.items():
            (self.folder / name).write_bytes(data)
        with (
            patch("installation.build", return_value=self.binary),
            patch("installation.launcher", return_value=self.root / "browser-hooks"),
            patch("installation.remove_autostart") as remove_autostart,
            patch("installation.stop") as stop,
            patch("service.start") as start,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            setup_hooks(self.home, self.checkout, self.root)
        remove_autostart.assert_called_once_with()
        stop.assert_called_once_with(self.home)
        start.assert_not_called()
        self.assertEqual(pairing.read_bytes(), b"synthetic-saved-key")
        for name, data in files.items():
            self.assertEqual((self.folder / name).read_bytes(), data)

    def test_private_extension_contains_only_browser_runtime_files(self):
        with (
            patch("slack.setup.shutil.which", return_value=sys.executable),
            patch("installation.build", return_value=self.binary),
            patch("installation.launcher", return_value=self.root / "browser-hooks"),
            patch("installation.remove_autostart"),
            patch("installation.stop"),
            contextlib.redirect_stdout(io.StringIO()) as output,
        ):
            setup_hooks(self.home, self.checkout, self.root)
        self.assertIn("Load unpacked", output.getvalue())
        self.assertIn("no code to copy", output.getvalue())
        extension = self.home / "extension"
        self.assertTrue((extension / "manifest.json").is_file())
        self.assertTrue((extension / "background.mjs").is_file())
        self.assertTrue((extension / "bridge.mjs").is_file())
        self.assertFalse((extension / "popup/index.js").exists())
        self.assertFalse((extension / "bridge").exists())
        self.assertFalse((extension / "slack/tests").exists())
        self.assertEqual(extension.stat().st_mode & 0o777, 0o700)
        self.assertEqual((extension / "manifest.json").stat().st_mode & 0o777, 0o600)

    def test_private_home_inside_repository_is_rejected_before_writing(self):
        result = subprocess.run(
            [
                sys.executable,
                str(self.checkout / "cli.py"),
                "setup",
                "--home",
                str(self.checkout / "private-state"),
            ],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the public repository", result.stderr)
        self.assertFalse((self.checkout / "private-state").exists())

    def test_one_private_home_override(self):
        with patch.dict("os.environ", {"BROWSER_HOOKS_HOME": str(self.home)}):
            self.assertEqual(app_home(), self.home)
        with (
            patch.dict("os.environ", {"BROWSER_HOOKS_HOME": ""}),
            patch("paths.Path.home", return_value=self.root),
        ):
            self.assertEqual(app_home(), self.root / ".local/share/browser-hooks")

    def test_launcher_reports_status_for_its_home_from_another_directory(self):
        self.configure()
        binary = self.home / "bin/browser-hooks-bridge"
        binary.parent.mkdir()
        binary.symlink_to(self.binary)
        with patch("installation.Path.home", return_value=self.root / "home with spaces"):
            executable = launcher(self.home, self.checkout)
        result = subprocess.run(
            [str(executable), "status"], cwd=self.root, capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("stopped; run browser-hooks start", result.stdout)
        self.assertIn(str(self.path), result.stdout)
        self.assertFalse((self.folder / "sessions.sqlite3").exists())

    def test_status_accepts_only_the_managed_bridge_health(self):
        self.configure()
        binary = self.home / "bin/browser-hooks-bridge"
        binary.parent.mkdir()
        binary.symlink_to(self.binary)
        healthy = {"pid": 123, "paired": True, "hooks": {"slack": {"error": None}}}
        with (
            patch("slack.setup.running", return_value=123),
            patch("slack.setup.health", return_value=healthy),
            contextlib.redirect_stdout(io.StringIO()) as output,
        ):
            self.assertEqual(status(self.home), 0)
        self.assertIn("Browser: paired", output.getvalue())
        with (
            patch("slack.setup.running", return_value=456),
            patch("slack.setup.health", return_value=healthy),
            contextlib.redirect_stdout(io.StringIO()) as output,
        ):
            self.assertEqual(status(self.home), 1)
        self.assertNotIn("Browser: paired", output.getvalue())

    def test_bad_config_and_missing_clis_leave_existing_data_untouched(self):
        with (
            patch("slack.setup.shutil.which", return_value=None),
            self.assertRaisesRegex(ValueError, "Install and sign in"),
        ):
            configure(self.home, self.checkout / "slack", self.root, self.binary)
        self.assertFalse(self.path.exists())
        self.path.parent.mkdir(parents=True)
        for contents in ("{broken", "{}"):
            self.path.write_text(contents)
            with self.assertRaisesRegex(ValueError, "configuration"):
                validate(self.home, self.binary)
            self.assertEqual(self.path.read_text(), contents)


if __name__ == "__main__":
    unittest.main()
