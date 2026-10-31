import os
import unittest
from unittest.mock import patch

import agent_slack


class StartupTests(unittest.TestCase):
    def test_arguments_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "configure keyword commands in .env"):
            agent_slack.main(["provider", "codex"])

    def test_missing_command_configuration_fails_before_slack_setup(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "AGENT_SLACK_COMMANDS"):
                agent_slack.main([])

    def test_missing_executable_fails_before_slack_setup(self):
        config = '{"work":{"start":["/missing/command"],"resume":["/missing/command","{session_id}"]}}'
        with patch.dict(os.environ, {"AGENT_SLACK_COMMANDS": config}, clear=True):
            with self.assertRaisesRegex(ValueError, "executable not found"):
                agent_slack.main([])


if __name__ == "__main__":
    unittest.main()
