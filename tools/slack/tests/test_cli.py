import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from agent_slack import cli
from agent_slack.environment import read_env


class ConfigurationTests(unittest.TestCase):
    def test_config_uses_its_directory_and_environment_overrides_without_shell_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            executable = root / "command"
            executable.write_text("#!/bin/sh\nexit 0\n")
            executable.chmod(0o700)
            config = root / ".env"
            commands = {"work": {"start": ["./command"], "resume": ["./command", "{session_id}"]}}
            config.write_text(
                "# Comments and quoted multiline JSON are supported.\n"
                "SLACK_APP_TOKEN=xapp-test\nSLACK_USER_TOKEN=xoxp-test\nSLACK_USER_ID=UFILE\n"
                f"AGENT_SLACK_WORKSPACE='{root}'\n"
                f"AGENT_SLACK_COMMANDS='{json.dumps(commands, indent=2)}'\n"
                "EXTRA_SETTING='literal $HOME `touch should-not-exist` $(touch should-not-exist)'\n"
            )
            config.chmod(0o600)
            previous = Path.cwd()
            try:
                os.chdir(root.parent)
                with (patch.dict(os.environ, {"SLACK_USER_ID": "UENV"}, clear=True),
                      patch.object(cli, "Application") as application):
                    cli.run(["--config", str(config)])
                    parsed = application.call_args.args[0]
                    self.assertEqual(parsed.user_id, "UENV")
                    self.assertEqual(parsed.commands["work"].start, (str(executable),))
                    self.assertEqual(Path.cwd(), root)
                    self.assertIn("$(touch should-not-exist)", os.environ["EXTRA_SETTING"])
                    self.assertFalse((root / "should-not-exist").exists())
                    application.return_value.run.assert_called_once()
            finally:
                os.chdir(previous)

    def test_unsafe_permissions_and_non_assignments_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / ".env"
            path.write_text("SLACK_APP_TOKEN=xapp-private\n")
            path.chmod(0o644)
            with self.assertRaisesRegex(ValueError, "permissions to 600"), patch.object(cli, "Application") as application:
                cli.run(["--config", str(path)])
            application.assert_not_called()
            path.chmod(0o600)
            path.write_text("invalid assignment\n")
            with self.assertRaisesRegex(ValueError, "KEY=value"):
                read_env(path)


if __name__ == "__main__":
    unittest.main()
