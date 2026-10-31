import json
import os
import unittest
from pathlib import Path
from unittest.mock import patch

from routing import command, command_profiles
from providers import ProviderSettings


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.profiles = {"chat": ProviderSettings("codex", "gpt-6.1-sol", "high"),
                         "claude": ProviderSettings("claude", "claude-opus-5-5", "high"),
                         "assist": ProviderSettings("pi")}
        self.projects = {"tonal": Path("/repos/tonal"), "mobile": Path("/repos/mobile"),
                         "api": Path("/repos/api-go")}

    def test_only_configured_words_at_the_start_trigger(self):
        for text in ["bot help", "fix the bot", "please chat help", "ask help", "C help", "Bot help",
                     " chat help", "chatbot help", "claudecode help", "bot: help", "chat.help"]:
            with self.subTest(text=text):
                self.assertIsNone(command(text, self.projects, self.profiles))
        for prefix in ["assist", "chat", "claude"]:
            for separator in [" ", "  ", "\t", "\n"]:
                with self.subTest(prefix=prefix, separator=separator):
                    self.assertEqual(command(prefix + separator + "help", self.projects, self.profiles).request, "help")
            self.assertIsNone(command(prefix, self.projects, self.profiles))

    def test_alias_can_appear_anywhere_and_stays_in_the_request(self):
        for text, alias in [("chat tonal fix this", "tonal"),
                            ("claude review the mobile login", "mobile"),
                            ("assist fix the error in API.", "api"),
                            ("chat review (mobile) tests", "mobile")]:
            with self.subTest(text=text):
                parsed = command(text, self.projects, self.profiles)
                self.assertEqual(parsed.workspace, self.projects[alias])
                self.assertEqual(parsed.request, text.split(maxsplit=1)[1])

    def test_partial_words_do_not_select_a_workspace(self):
        for request in ["tonality", "automobile", "capital", "api-key", "mobile_app", "my-tonal"]:
            with self.subTest(request=request):
                self.assertIsNone(command("assist explain " + request, self.projects, self.profiles).workspace)

    def test_first_alias_in_text_wins_regardless_of_configuration_order(self):
        self.assertEqual(command("chat tonal fix tonal tests", self.projects, self.profiles).workspace,
                         self.projects["tonal"])
        for request, alias in [("compare mobile and api", "mobile"),
                               ("compare api and mobile", "api"),
                               ("mobile api tonal", "mobile"),
                               ("compare (API), tonal and mobile", "api")]:
            with self.subTest(request=request):
                parsed = command("chat " + request, self.projects, self.profiles)
                self.assertEqual(parsed.workspace, self.projects[alias])
                self.assertEqual(parsed.request, request)


class CommandConfigurationTests(unittest.TestCase):
    def test_arbitrary_keywords_load_their_own_settings(self):
        config = {
            "work": {"provider": "codex", "model": "my-model", "reasoning_effort": "high", "tier": "fast"},
            "Review": {"provider": "claude", "model": "opus", "reasoning_effort": "medium"},
            "!ask": {"provider": "pi"},
        }
        with patch.dict(os.environ, {"SLACK_REPLY_COMMANDS": json.dumps(config)}, clear=True):
            profiles = command_profiles()
        self.assertEqual(profiles["work"], ProviderSettings("codex", "my-model", "high", "fast"))
        self.assertEqual(profiles["Review"], ProviderSettings("claude", "opus", "medium"))
        self.assertEqual(profiles["!ask"], ProviderSettings("pi"))
        self.assertEqual(command("Review inspect this", {}, profiles).settings, profiles["Review"])
        self.assertIsNone(command("review inspect this", {}, profiles))
        self.assertIsNone(command("chat inspect this", {}, profiles))
        self.assertIsNone(command("claude inspect this", {}, profiles))
        self.assertIsNone(command("bot inspect this", {}, profiles))

    def test_commands_are_required_and_must_be_a_nonempty_object(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "SLACK_REPLY_COMMANDS"):
                command_profiles()
        for raw in ["", "bad json", "null", "[]", "{}"]:
            with self.subTest(raw=raw), patch.dict(os.environ, {"SLACK_REPLY_COMMANDS": raw}):
                with self.assertRaises(ValueError):
                    command_profiles()

    def test_keyword_names_do_not_imply_a_provider(self):
        config = {"claude": {"provider": "codex"}, "chat": {"provider": "pi"}}
        with patch.dict(os.environ, {"SLACK_REPLY_COMMANDS": json.dumps(config)}):
            profiles = command_profiles()
        self.assertEqual(command("claude help", {}, profiles).settings.provider, "codex")
        self.assertEqual(command("chat help", {}, profiles).settings.provider, "pi")

    def test_invalid_keywords_or_profile_fields_are_rejected(self):
        invalid = [
            {"": {"provider": "codex"}}, {"two words": {"provider": "codex"}},
            {" chat": {"provider": "codex"}}, {"chat\u0000": {"provider": "codex"}},
            {"work": None}, {"work": "codex"}, {"work": {}},
            {"work": {"provider": "unknown"}}, {"work": {"provider": "codex", "model": 1}},
            {"work": {"provider": "codex", "reasoning_effort": None}},
            {"work": {"provider": "codex", "tier": "priority"}},
            {"work": {"provider": "codex", "effort": "high"}},
        ]
        for config in invalid:
            with self.subTest(config=config), patch.dict(os.environ, {"SLACK_REPLY_COMMANDS": json.dumps(config)}):
                with self.assertRaises(ValueError):
                    command_profiles()


if __name__ == "__main__":
    unittest.main()
