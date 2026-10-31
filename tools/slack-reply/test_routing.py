import unittest
from pathlib import Path

from routing import command


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.projects = {"tonal": Path("/repos/tonal"), "mobile": Path("/repos/mobile"),
                         "api": Path("/repos/api-go")}

    def test_only_complete_lowercase_prefixes_at_the_start_trigger(self):
        for text in ["fix the bot", "please chat help", "ask help", "C help", "Bot help",
                     " chat help", "chatbot help", "claudecode help", "bot: help", "chat.help"]:
            with self.subTest(text=text):
                self.assertIsNone(command(text, self.projects))
        for prefix in ["bot", "chat", "claude"]:
            for separator in [" ", "  ", "\t", "\n"]:
                with self.subTest(prefix=prefix, separator=separator):
                    self.assertEqual(command(prefix + separator + "help", self.projects).request, "help")
            self.assertIsNone(command(prefix, self.projects))

    def test_alias_can_appear_anywhere_and_stays_in_the_request(self):
        for text, alias in [("chat tonal fix this", "tonal"),
                            ("claude review the mobile login", "mobile"),
                            ("bot fix the error in API.", "api"),
                            ("chat review (mobile) tests", "mobile")]:
            with self.subTest(text=text):
                parsed = command(text, self.projects)
                self.assertEqual(parsed.workspace, self.projects[alias])
                self.assertEqual(parsed.request, text.split(maxsplit=1)[1])

    def test_partial_words_do_not_select_a_workspace(self):
        for request in ["tonality", "automobile", "capital", "api-key", "mobile_app", "my-tonal"]:
            with self.subTest(request=request):
                self.assertIsNone(command("bot explain " + request, self.projects).workspace)

    def test_repeated_alias_is_one_workspace_but_distinct_aliases_are_ambiguous(self):
        self.assertEqual(command("chat tonal fix tonal tests", self.projects).workspace,
                         self.projects["tonal"])
        with self.assertRaisesRegex(ValueError, "only one project alias"):
            command("chat compare mobile and api", self.projects)


if __name__ == "__main__":
    unittest.main()
