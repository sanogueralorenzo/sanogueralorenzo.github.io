import json
import os
import unittest
from pathlib import Path
from unittest.mock import patch

from routing import command, command_providers


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.commands = {"chat": "codex",
                         "claude": "claude",
                         "assist": "pi"}
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


class CommandConfigurationTests(unittest.TestCase):
    def test_arbitrary_keywords_select_their_cli(self):
        config = {
            "work": "codex",
            "Review": "claude",
            "!ask": "pi",
        }
        with patch.dict(os.environ, {"AGENT_SLACK_COMMANDS": json.dumps(config)}, clear=True):
            commands = command_providers()
        self.assertEqual(commands["work"], "codex")
        self.assertEqual(commands["Review"], "claude")
        self.assertEqual(commands["!ask"], "pi")
        self.assertEqual(command("Review inspect this", {}, commands).provider, commands["Review"])
        self.assertIsNone(command("review inspect this", {}, commands))
        self.assertIsNone(command("chat inspect this", {}, commands))
        self.assertIsNone(command("claude inspect this", {}, commands))
        self.assertIsNone(command("bot inspect this", {}, commands))

    def test_commands_are_required_and_must_be_a_nonempty_object(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "AGENT_SLACK_COMMANDS"):
                command_providers()
        for raw in ["", "bad json", "null", "[]", "{}"]:
            with self.subTest(raw=raw), patch.dict(os.environ, {"AGENT_SLACK_COMMANDS": raw}):
                with self.assertRaises(ValueError):
                    command_providers()

    def test_keyword_names_do_not_imply_a_provider(self):
        config = {"claude": "codex", "chat": "pi"}
        with patch.dict(os.environ, {"AGENT_SLACK_COMMANDS": json.dumps(config)}):
            commands = command_providers()
        self.assertEqual(command("claude help", {}, commands).provider, "codex")
        self.assertEqual(command("chat help", {}, commands).provider, "pi")

    def test_invalid_keywords_or_providers_are_rejected(self):
        invalid = [
            {"": "codex"}, {"two words": "codex"},
            {" chat": "codex"}, {"chat\u0000": "codex"},
            {"work": None}, {"work": 1}, {"work": {}}, {"work": []},
            {"work": "unknown"}, {"work": ""}, {"work": "codex --model other"},
            {"work": {"provider": "codex"}},
        ]
        for config in invalid:
            with self.subTest(config=config), patch.dict(os.environ, {"AGENT_SLACK_COMMANDS": json.dumps(config)}):
                with self.assertRaises(ValueError):
                    command_providers()


if __name__ == "__main__":
    unittest.main()
