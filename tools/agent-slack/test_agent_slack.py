import os
import unittest
from unittest.mock import patch

import agent_slack


class StartupTests(unittest.TestCase):
    def test_removed_provider_command_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "configure keyword commands in .env"):
            agent_slack.main(["provider", "codex"])

    def test_missing_command_configuration_fails_before_slack_setup(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "AGENT_SLACK_COMMANDS"):
                agent_slack.main([])

    def test_configured_provider_is_validated_before_slack_setup(self):
        with patch.dict(os.environ, {"AGENT_SLACK_COMMANDS": '{"work":"codex"}'}, clear=True):
            with patch.object(agent_slack, "require_available", side_effect=RuntimeError("codex CLI is not installed")) as available:
                with self.assertRaisesRegex(RuntimeError, "codex CLI is not installed"):
                    agent_slack.main([])
        available.assert_called_once_with("codex")


if __name__ == "__main__":
    unittest.main()
