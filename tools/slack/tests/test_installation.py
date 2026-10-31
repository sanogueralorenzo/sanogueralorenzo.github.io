import io
import json
import os
import plistlib
import pty
import select
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import ExitStack, redirect_stdout
from pathlib import Path
from unittest.mock import Mock, patch
from urllib.parse import parse_qs, urlsplit

from slack_sdk.errors import SlackApiError

import installation
from state import Session, State


SOURCE = Path(__file__).resolve().parent.parent


class Auth(dict):
    def __init__(self, scopes):
        super().__init__(user_id="U123", team_id="T123")
        self.headers = {"x-oauth-scopes": scopes}


class InstallationTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.home = Path(directory.name) / "home space & 100%"
        self.root = self.home / ".local/share/agent-slack"
        (self.root / "wrappers").mkdir(parents=True)
        (self.root / ".venv/bin").mkdir(parents=True)
        (self.root / ".venv/bin/python").symlink_to(sys.executable)
        (self.root / "wrappers/codex.py").touch()
        self.bin = self.home / "bin"
        self.bin.mkdir()
        (self.bin / "codex").write_text("#!/bin/sh\nexit 0\n")
        (self.bin / "codex").chmod(0o700)
        self.manifest = json.loads((SOURCE / "manifest.json").read_text())
        self.client = Mock()
        self.client.auth_test.return_value = Auth(",".join(self.manifest["oauth_config"]["scopes"]["user"]))
        self.output = io.StringIO()
        stack = ExitStack()
        self.addCleanup(stack.close)
        for patcher in (patch.object(installation, "ROOT", self.root),
                        patch.object(Path, "home", return_value=self.home),
                        patch.dict(os.environ, {"HOME": str(self.home), "PATH": f"{self.bin}:/usr/bin:/bin"}, clear=True),
                        patch.object(installation.platform, "system", return_value="Darwin"),
                        patch.object(installation.webbrowser, "open"),
                        redirect_stdout(self.output)):
            stack.enter_context(patcher)
        self.ask = stack.enter_context(patch.object(installation, "ask_token", return_value=""))
        self.sdk = stack.enter_context(patch("slack_sdk.WebClient", return_value=self.client))
        self.run = stack.enter_context(patch.object(installation.subprocess, "run"))

    def tokens(self):
        os.environ.update(SLACK_APP_TOKEN="xapp-test-secret", SLACK_USER_TOKEN="xoxp-test-secret")

    def values(self):
        return dict(item.split("=", 1) for item in shlex.split((self.root / ".env").read_text()))

    def test_waiting_for_approval_saves_defaults_and_provides_the_manifest(self):
        self.ask.side_effect = ["xapp-test-secret", ""]
        self.assertFalse(installation.configure(self.manifest))
        values = self.values()
        self.assertEqual(values["AGENT_SLACK_WORKSPACE"], str(self.home))
        commands = json.loads(values["AGENT_SLACK_COMMANDS"])
        self.assertEqual(set(commands), {"chat"})
        self.assertEqual(commands["chat"]["start"][0], str(self.root / ".venv/bin/python"))
        self.assertEqual((self.root / ".env").stat().st_mode & 0o777, 0o600)
        url = installation.webbrowser.open.call_args.args[0]
        self.assertEqual(json.loads(parse_qs(urlsplit(url).query)["manifest_json"][0]), self.manifest)
        self.assertEqual(values["SLACK_APP_TOKEN"], "xapp-test-secret")
        self.ask.side_effect = None
        self.assertFalse(installation.configure(self.manifest))
        self.assertEqual(installation.webbrowser.open.call_args.args[0], "https://api.slack.com/apps")
        self.assertNotIn("test-secret", self.output.getvalue())
        self.sdk.assert_not_called()
        self.run.assert_not_called()

    def test_approved_install_detects_identity_and_writes_background_services(self):
        self.tokens()
        for system in ("Darwin", "Linux"):
            with self.subTest(system=system):
                if system == "Linux":
                    self.client.auth_test.return_value.headers["x-oauth-scopes"] = self.manifest["oauth_config"]["scopes"]["user"]
                config = installation.configure(self.manifest)
                installation.start_service(system, config)
                self.assertEqual(config.user_id, "U123")
                self.assertEqual(self.values()["SLACK_USER_ID"], "U123")
                target = installation.service_path(system)
                if system == "Darwin":
                    data = plistlib.loads(target.read_bytes())
                    self.assertEqual(data["ProgramArguments"], [str(self.root / "run.sh")])
                    self.assertEqual(data["WorkingDirectory"], str(self.root))
                    self.assertNotIn("SLACK_USER_TOKEN", data["EnvironmentVariables"])
                    log = config.state_dir / "agent-slack.log"
                    self.assertEqual(log.stat().st_mode & 0o777, 0o600)
                    self.run.assert_called_with(["launchctl", "bootstrap", f"gui/{os.getuid()}", str(target)], check=True)
                else:
                    unit = target.read_text()
                    self.assertIn(f'ExecStart="{str(self.root).replace("%", "%%")}/run.sh"', unit)
                    self.assertIn("KillMode=mixed", unit)
                    self.assertNotIn("xoxp-", unit)
                    self.run.assert_any_call(["systemctl", "--user", "enable", "--now", f"{installation.SERVICE}.service"], check=True)
                    self.run.assert_any_call(["loginctl", "enable-linger"], check=False, capture_output=True)
        self.ask.assert_not_called()
        self.assertNotIn("test-secret", self.output.getvalue())

    def test_reconfiguration_preserves_commands_projects_and_saved_sessions(self):
        self.tokens()
        config = installation.configure(self.manifest)
        workspace = self.home / "repo"
        workspace.mkdir()
        values = self.values()
        commands = {"work": {"start": ["/bin/sh"], "resume": ["/bin/sh", "{session_id}"]}}
        values.update(AGENT_SLACK_COMMANDS=json.dumps(commands), AGENT_SLACK_WORKSPACE=str(workspace),
                      AGENT_SLACK_PROJECTS=json.dumps({"repo": str(workspace)}), EXTRA_SETTING="spaces and 'quotes' # literal $HOME")
        installation.save_config(values)
        # The shell launcher sources the existing file before calling configuration on an update.
        os.environ.update(values)
        session = Session("command", "saved-id", workspace, "1.000001")
        state = State(config.state_dir)
        self.addCleanup(state.close)
        state.save_session("T123", "C123", "1.000001", session)
        updated = installation.configure(self.manifest)
        self.assertEqual(updated.workspace, workspace.resolve())
        self.assertEqual(updated.projects, {"repo": workspace.resolve()})
        self.assertEqual(set(updated.commands), {"work"})
        self.assertEqual(self.values()["EXTRA_SETTING"], values["EXTRA_SETTING"])
        self.assertEqual(state.session("T123", "C123", "1.000001"), session)
        self.ask.assert_not_called()

    def test_missing_permissions_do_not_start_a_service_or_leak_tokens(self):
        self.tokens()
        self.client.auth_test.return_value.headers["x-oauth-scopes"] = "chat:write"
        with self.assertRaisesRegex(ValueError, "Approve/reinstall") as error:
            installation.configure(self.manifest)
        self.assertNotIn("test-secret", str(error.exception) + self.output.getvalue())
        self.run.assert_not_called()
        self.assertFalse(installation.service_path("Darwin").exists())
        self.client.auth_test.side_effect = SlackApiError("SDK detail with xoxp-test-secret", {"error": "invalid_auth"})
        with self.assertRaisesRegex(ValueError, "invalid_auth") as error:
            installation.configure(self.manifest)
        self.assertNotIn("test-secret", str(error.exception) + self.output.getvalue())


class BootstrapTests(unittest.TestCase):
    def test_shell_install_and_update_preserve_configuration_and_replace_managed_code(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            home = base / "home space"
            home.mkdir()
            fixture = base / "repo"
            shutil.copytree(SOURCE, fixture / "tools/slack",
                            ignore=shutil.ignore_patterns(".env", ".venv", ".runtime", "__pycache__"))
            bins = base / "bin"
            bins.mkdir()
            scripts = {
                "git": '''import os, shutil, sys
from pathlib import Path
if sys.argv[1] == "clone":
    shutil.copytree(os.environ["TEST_SOURCE"], sys.argv[-1])
elif "rev-parse" in sys.argv:
    print("test123")
''',
                "curl": '''import sys
from pathlib import Path
Path(sys.argv[-1]).write_text('mkdir -p "$UV_UNMANAGED_INSTALL"\\ncp "$TEST_UV" "$UV_UNMANAGED_INSTALL/uv"\\nchmod 700 "$UV_UNMANAGED_INSTALL/uv"\\n')
''',
                "codex": "pass\n",
                "uv": '''import os, sys
from pathlib import Path
if sys.argv[1:3] == ["python", "find"]:
    print(sys.executable)
elif sys.argv[1] == "venv":
    target = Path(sys.argv[-1]) / "bin"
    target.mkdir(parents=True, exist_ok=True)
    (target / "python").write_text("#!" + sys.executable + "\\n" + "import sys\\nfrom pathlib import Path\\nsys.path.insert(0, str(Path(sys.argv[1]).resolve().parent))\\nimport installation\\ninstallation.ask_token = lambda _: ''\\ninstallation.webbrowser.open = lambda _: False\\nsys.argv = sys.argv[1:]\\ninstallation.main()\\n")
    (target / "python").chmod(0o700)
''',
            }
            for name, body in scripts.items():
                executable = bins / name
                executable.write_text(f"#!{sys.executable}\n" + body)
                executable.chmod(0o700)
            env = {"HOME": str(home), "PATH": f"{bins}:/usr/bin:/bin", "TEST_SOURCE": str(fixture), "TEST_UV": str(bins / "uv")}
            script = (SOURCE / "install.sh").read_text()
            result = subprocess.run(["sh"], input=script, env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            root = home / ".local/share/agent-slack"
            self.assertTrue((root / ".env").exists())
            self.assertTrue((root / ".runtime/uv").exists())
            self.assertIn("Local setup is ready", result.stdout)
            with (root / ".env").open("a") as output:
                output.write("EXTRA_SETTING='keep me'\n")
            (root / "src/obsolete.py").touch()
            state = home / ".local/state/agent-slack"
            state.mkdir(parents=True)
            (state / "keep").write_text("history")
            result = subprocess.run(["sh"], input=script, env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("EXTRA_SETTING='keep me'", (root / ".env").read_text())
            self.assertFalse((root / "src/obsolete.py").exists())
            self.assertEqual((state / "keep").read_text(), "history")


class TokenPromptTests(unittest.TestCase):
    def test_hidden_token_prompt_reads_terminal_even_with_stdin_closed(self):
        token = "xapp-private-test-value"
        pid, terminal = pty.fork()
        if pid == 0:
            os.dup2(os.open(os.devnull, os.O_RDONLY), 0)
            code = "from installation import ask_token; print('accepted=' + str(ask_token('App token: ') == '" + token + "'))"
            os.execl(sys.executable, sys.executable, "-c", code)
        output = bytearray()

        def read_until(marker):
            deadline = time.monotonic() + 5
            while marker not in output:
                ready, _, _ = select.select([terminal], [], [], max(0, deadline - time.monotonic()))
                self.assertTrue(ready, "Token prompt did not complete")
                output.extend(os.read(terminal, 4096))

        try:
            read_until(b"App token: ")
            os.write(terminal, (token + "\n").encode())
            read_until(b"accepted=True")
            self.assertNotIn(token.encode(), output)
        finally:
            if os.waitpid(pid, os.WNOHANG)[0] == 0:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(terminal)


if __name__ == "__main__":
    unittest.main()
