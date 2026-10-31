import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from commands import Command
from routing import command_for, project_workspaces


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.commands = {keyword: Command((name,), (name, "{session_id}"))
                         for keyword, name in (("chat", "tool"), ("review", "other"))}
        self.projects = {"project": Path("/repos/project"), "api": Path("/repos/api")}

    def parse(self, text="chat help", **extra):
        event = {"type": "message", "user": "U123", "channel": "C123", "ts": "1.000001", "text": text, **extra}
        return command_for(event, "U123", self.projects, self.commands)

    def test_only_authorized_messages_starting_with_a_complete_keyword_trigger(self):
        for keyword in self.commands:
            for separator in (" ", "\t", "\n"):
                parsed = self.parse(keyword + separator + "help", subtype="thread_broadcast")
                self.assertEqual(parsed.command, self.commands[keyword])
                self.assertEqual(parsed.request, "help")
        for text in ("chat", "chat ", " chat help", "Chat help", "chatbot help", "chat: help", "please chat help", "<@U123> chat help"):
            with self.subTest(text=text):
                self.assertIsNone(self.parse(text))
        for extra in ({"user": "OTHER"}, {"bot_id": "B123"}, {"app_id": "A123"},
                      {"subtype": "message_changed"}, {"type": "app_mention"}, {"channel": ""}, {"ts": ""}):
            with self.subTest(extra=extra):
                self.assertIsNone(self.parse(**extra))

    def test_first_complete_alias_selects_workspace_and_preserves_request(self):
        for request, workspace in (("compare (API), project", self.projects["api"]),
                                   ("explain PROJECT and api", self.projects["project"]),
                                   ("explain my-project api-key api_client", None), ("help", None)):
            with self.subTest(request=request):
                parsed = self.parse("chat " + request)
                self.assertEqual(parsed.workspace, workspace)
                self.assertEqual(parsed.request, request)

    def test_project_mapping_is_optional_and_resolves_directories(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(project_workspaces(), {})
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, {"AGENT_SLACK_PROJECTS": json.dumps({"work": directory})}):
                self.assertEqual(project_workspaces(), {"work": Path(directory).resolve()})

    def test_invalid_project_mapping_is_rejected(self):
        for config in ('[]', '{"Bad": "/tmp"}', '{"work": ""}', '{"work": "/nonexistent-agent-slack"}'):
            with self.subTest(config=config), patch.dict(os.environ, {"AGENT_SLACK_PROJECTS": config}):
                with self.assertRaises(ValueError):
                    project_workspaces()


if __name__ == "__main__":
    unittest.main()
