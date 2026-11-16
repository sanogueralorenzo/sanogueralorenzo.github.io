import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from installation import install as install_hooks, launcher
from paths import app_home
from slack.setup import configure, validate
from service import install as install_service, linux_unit, specification
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

    def test_update_preserves_config_pairing_and_database_and_installs_native_service(
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
            patch("service.install") as service,
            patch("service.health", return_value={"paired": True}),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            install_hooks(self.home, self.checkout, self.root)
        service.assert_called_once_with(self.binary, self.home)
        self.assertEqual(pairing.read_bytes(), b"synthetic-saved-key")
        for name, data in files.items():
            self.assertEqual((self.folder / name).read_bytes(), data)
        self.assertEqual(
            specification(self.binary, self.home)["ProgramArguments"],
            [str(self.binary), "serve", "--home", str(self.home)],
        )

    def test_private_extension_contains_only_browser_runtime_files(self):
        with (
            patch("slack.setup.shutil.which", return_value=sys.executable),
            patch("installation.build", return_value=self.binary),
            patch("installation.launcher", return_value=self.root / "browser-hooks"),
            patch("service.install"),
            patch("service.health", return_value={"paired": False}),
            contextlib.redirect_stdout(io.StringIO()) as output,
        ):
            install_hooks(self.home, self.checkout, self.root)
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
                "install",
                "--home",
                str(self.checkout / "private-state"),
            ],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("outside the public repository", result.stderr)
        self.assertFalse((self.checkout / "private-state").exists())

    def test_launcher_executes_from_any_directory_and_serve_executes_native_binary(
        self,
    ):
        with patch(
            "installation.Path.home", return_value=self.root / "home with spaces"
        ):
            path = launcher(self.home, self.checkout)
        result = subprocess.run(
            [str(path), "slack", "--help"],
            cwd=self.root,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("status", result.stdout)
        self.assertNotIn("serve", result.stdout)
        self.assertEqual(path.stat().st_mode & 0o777, 0o700)
        binary = self.home / "bin/browser-hooks-bridge"
        binary.parent.mkdir(parents=True)
        binary.write_text(
            "#!"
            + sys.executable
            + "\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n"
        )
        binary.chmod(0o700)
        result = subprocess.run(
            [str(path), "serve"], cwd=self.root, capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["serve", "--home", str(self.home)])

    def test_one_private_home_override(self):
        with patch.dict("os.environ", {"BROWSER_HOOKS_HOME": str(self.home)}):
            self.assertEqual(app_home(), self.home)
        with (
            patch.dict("os.environ", {"BROWSER_HOOKS_HOME": ""}),
            patch("paths.Path.home", return_value=self.root),
        ):
            self.assertEqual(app_home(), self.root / ".local/share/browser-hooks")

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

    def test_macos_update_waits_for_previous_service_to_exit(self):
        from service import install

        completed = lambda code: Mock(returncode=code)
        with (
            patch("service.sys.platform", "darwin"),
            patch("service.Path.home", return_value=self.root),
            patch("service.time.sleep"),
            patch(
                "service.subprocess.run",
                side_effect=[completed(0), completed(0), completed(5), completed(0)],
            ) as run,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            install(self.binary, self.home)
        self.assertEqual(
            sum(c.args[0][1] == "bootstrap" for c in run.call_args_list), 2
        )

    def test_linux_service_uses_native_binary_and_only_explicit_path(self):
        unit = linux_unit(self.root / "with spaces/browser-hooks-bridge", self.home)
        self.assertIn('with spaces/browser-hooks-bridge" "serve" "--home"', unit)
        self.assertIn("UMask=0077", unit)
        self.assertNotIn("SLACK_", unit)
        self.assertEqual(
            set(specification(self.binary, self.home)["EnvironmentVariables"]), {"PATH"}
        )
        with (
            patch("service.sys.platform", "linux"),
            patch("service.Path.home", return_value=self.root),
            patch("service.subprocess.run") as run,
            contextlib.redirect_stdout(io.StringIO()),
        ):
            run.return_value.returncode = 0
            install_service(self.binary, self.home)
        self.assertEqual(
            [c.args[0][2] for c in run.call_args_list],
            ["daemon-reload", "enable", "restart"],
        )
        self.assertEqual(
            (self.home / "logs/bridge.log").stat().st_mode & 0o777, 0o600
        )


if __name__ == "__main__":
    unittest.main()
