import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from commands import Command
from routing import command, project_workspaces


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.commands = {keyword: Command((name,), (name, "{session_id}"))
                         for keyword, name in (("chat", "custom-one"), ("claude", "custom-two"),
                                               ("assist", "custom-one"))}
        self.projects = {"tonal": Path("/repos/tonal"), "mobile": Path("/repos/mobile"),
                         "api": Path("/repos/api-go")}

    def test_only_configured_words_at_the_start_trigger(self):
        for text in ["bot help", "fix the bot", "please chat help", "ask help", "C help", "Bot help",
                     " chat help", "chatbot help", "claudecode help", "bot: help", "chat.help"]:
            with self.subTest(text=text):
                self.assertIsNone(command(text, self.projects, self.commands))
        for prefix in ["assist", "chat", "claude"]:
            for separator in [" ", "  ", "\t", "\n"]:
                with self.subTest(prefix=prefix, separator=separator):
                    self.assertEqual(command(prefix + separator + "help", self.projects, self.commands).request, "help")
            self.assertIsNone(command(prefix, self.projects, self.commands))

    def test_alias_can_appear_anywhere_and_stays_in_the_request(self):
        for text, alias in [("chat tonal fix this", "tonal"),
                            ("claude review the mobile login", "mobile"),
                            ("assist fix the error in API.", "api"),
                            ("chat review (mobile) tests", "mobile")]:
            with self.subTest(text=text):
                parsed = command(text, self.projects, self.commands)
                self.assertEqual(parsed.workspace, self.projects[alias])
                self.assertEqual(parsed.request, text.split(maxsplit=1)[1])

    def test_partial_words_do_not_select_a_workspace(self):
        for request in ["tonality", "automobile", "capital", "api-key", "mobile_app", "my-tonal"]:
            with self.subTest(request=request):
                self.assertIsNone(command("assist explain " + request, self.projects, self.commands).workspace)

    def test_first_alias_in_text_wins_regardless_of_configuration_order(self):
        self.assertEqual(command("chat tonal fix tonal tests", self.projects, self.commands).workspace,
                         self.projects["tonal"])
        for request, alias in [("compare mobile and api", "mobile"),
                               ("compare api and mobile", "api"),
                               ("mobile api tonal", "mobile"),
                               ("compare (API), tonal and mobile", "api")]:
            with self.subTest(request=request):
                parsed = command("chat " + request, self.projects, self.commands)
                self.assertEqual(parsed.workspace, self.projects[alias])
                self.assertEqual(parsed.request, request)


class ConfigurationTests(unittest.TestCase):
    def test_project_mapping_is_optional_and_resolves_directories(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(project_workspaces(), {})
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, {"AGENT_SLACK_PROJECTS": json.dumps({"work": directory})}):
                self.assertEqual(project_workspaces(), {"work": Path(directory).resolve()})

    def test_invalid_project_config_is_rejected(self):
        for config in ['invalid json', '[]', 'null', '{"Bad": "/tmp"}',
                       '{"two words": "/tmp"}', '{"work": 3}', '{"work": ""}',
                       '{"work": "/nonexistent-agent-slack-project"}']:
            with self.subTest(config=config), patch.dict(os.environ, {"AGENT_SLACK_PROJECTS": config}):
                with self.assertRaises(ValueError):
                    project_workspaces()


if __name__ == "__main__":
    unittest.main()
