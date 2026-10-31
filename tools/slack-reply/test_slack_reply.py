import os
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import slack_reply as reply


USER = "U123ABC"
ROOT = "1700000000.000001"
FIRST = "1700000001.000001"
SECOND = "1700000002.000001"


def event(ts=FIRST, text="bot question", **extra):
    return {"type": "message", "user": USER, "channel": "C123", "ts": ts,
            "text": text, **extra}


class FakeClient:
    def __init__(self):
        self.pages = []
        self.calls = []
        self.posts = []

    def conversations_replies(self, **kwargs):
        self.calls.append(kwargs)
        return self.pages.pop(0)

    def chat_postMessage(self, **kwargs):
        self.posts.append(kwargs)
        return {"ts": f"1700000003.{len(self.posts):06d}"}


class SlackReplyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.state = reply.State(self.path / "state")
        self.addCleanup(self.state.db.close)
        self.client = FakeClient()
        self.runner = Mock()
        provider_env = patch.dict(os.environ, {"SLACK_REPLY_PROVIDER": "codex"})
        provider_env.start()
        self.addCleanup(provider_env.stop)
        self.projects = {"project": self.path / "project", "service": self.path / "service"}
        for directory in self.projects.values():
            directory.mkdir()

    def handle(self, message):
        reply.handle(message, "T123", USER, self.client, self.state, self.path, self.path, self.projects)

    def test_trigger_requires_same_author_and_exact_prefix(self):
        for text in ["bot question", "chat question", "claude question", "chat\tquestion", "bot\nquestion"]:
            self.assertTrue(reply.eligible(event(text=text), USER))
        self.assertTrue(reply.eligible(event(subtype="thread_broadcast"), USER))
        for overrides in [
            {"user": "UOTHER"}, {"bot_id": "B123"}, {"app_id": "A123"},
            {"subtype": "bot_message"}, {"subtype": "message_changed"},
            {"type": "app_mention"}, {"channel": ""}, {"ts": ""},
        ]:
            with self.subTest(overrides=overrides):
                self.assertFalse(reply.eligible(event(**overrides), USER))
        for text in ["C question", "Bot question", " CHAT question", "please chat help", "chatbot help",
                     "claudecode help", f"question <@{USER}>", f"<@{USER}> bot question"]:
            with self.subTest(text=text):
                self.assertFalse(reply.eligible(event(text=text), USER))

    def test_unauthorized_users_and_mentions_never_run_provider(self):
        with patch.object(reply, "provider_for") as factory:
            self.handle(event(user="UOTHER"))
            self.handle(event(text=f"question <@{USER}>"))
            self.handle(event(text=f"<@{USER}> C question"))
        factory.assert_not_called()
        self.assertEqual(self.client.posts, [])
        self.assertEqual(self.client.calls, [])

    def test_empty_commands_are_ignored(self):
        with patch.object(reply, "provider_for") as factory:
            for text in ["bot", "bot ", "chat   ", "claude\n"]:
                with self.subTest(text=text):
                    self.assertIsNone(reply.command(text, self.projects))
                    self.handle(event(text=text))
        factory.assert_not_called()

    def test_prefix_selects_provider_and_profile_before_matching_workspace(self):
        os.environ["SLACK_REPLY_PROVIDER"] = "pi"
        for index, (prefix, provider, model, effort) in enumerate([
            ("bot", "pi", None, None),
            ("chat", "codex", "gpt-6.1-sol", "high"),
            ("claude", "claude", "claude-opus-5-5", "high"),
        ]):
            with self.subTest(prefix=prefix):
                self.runner.run.return_value = (f"session-{index}", "answer")
                with patch.object(reply, "provider_for", return_value=self.runner) as factory:
                    self.handle(event(ts=f"1700000001.{index:06d}", text=f"{prefix} explain the PROJECT build"))
                factory.assert_called_once_with(provider, self.projects["project"], self.path,
                                                model=model, effort=effort)
                self.assertTrue(self.runner.run.call_args.args[0].endswith("explain the PROJECT build"))

    def test_ambiguous_workspace_gets_a_reply_without_running_a_cli(self):
        request = event(text="chat compare project and service")
        with patch.object(reply, "provider_for") as factory:
            self.handle(request)
            self.handle(request)
        factory.assert_not_called()
        self.assertEqual(len(self.client.posts), 1)
        self.assertIn("only one project alias", self.client.posts[0]["markdown_text"])

    def test_alias_workspace_sticks_without_alias_and_survives_restart(self):
        self.runner.run.side_effect = [("project-session", "answer"),
                                       ("project-session", "followup answer")]
        root = event(ts=ROOT, text="bot project first question")
        followup = event(text="bot follow up", thread_ts=ROOT)
        self.client.pages = [{"messages": [root, followup]}]
        with patch.object(reply, "provider_for", return_value=self.runner) as factory:
            self.handle(root)
            self.state.db.close()
            self.state = reply.State(self.path / "state")
            self.addCleanup(self.state.db.close)
            self.handle(followup)
        self.assertEqual([call.args[1] for call in factory.call_args_list],
                         [self.projects["project"], self.projects["project"]])
        self.assertEqual([call.args[1] for call in self.runner.run.call_args_list],
                         [None, "project-session"])
        self.assertTrue(self.runner.run.call_args.args[0].endswith("Current request:\nfollow up"))

    def test_explicit_workspace_switch_starts_fresh_and_keeps_thread_provider(self):
        self.state.save_session("T123", "C123", ROOT, "claude", "old-session",
                                self.projects["project"])
        os.environ["SLACK_REPLY_PROVIDER"] = "pi"
        switches = [event(ts=FIRST, text="claude service fix", thread_ts=ROOT),
                    event(ts=SECOND, text="claude continue", thread_ts=ROOT),
                    event(ts="1700000004.000001", text="claude project back", thread_ts=ROOT)]
        self.client.pages = [{"messages": [message]} for message in switches]
        self.runner.run.side_effect = [("service-session", "answer"),
                                       ("service-session", "answer"),
                                       ("fresh-project-session", "answer")]
        with patch.object(reply, "provider_for", return_value=self.runner) as factory:
            for message in switches:
                self.handle(message)
        self.assertEqual([call.args[0] for call in factory.call_args_list],
                         ["claude", "claude", "claude"])
        self.assertEqual([call.args[1] for call in factory.call_args_list],
                         [self.projects["service"], self.projects["service"], self.projects["project"]])
        self.assertEqual([call.args[1] for call in self.runner.run.call_args_list],
                         [None, "service-session", None])

    def test_explicit_same_workspace_resumes_session(self):
        self.state.save_session("T123", "C123", ROOT, "codex", "same-session",
                                self.projects["project"])
        self.client.pages = [{"messages": [event(thread_ts=ROOT)]}]
        self.runner.run.return_value = ("same-session", "answer")
        with patch.object(reply, "provider_for", return_value=self.runner):
            self.handle(event(text="bot project continue", thread_ts=ROOT))
        self.assertEqual(self.runner.run.call_args.args[1], "same-session")

    def test_legacy_session_without_workspace_is_never_resumed(self):
        self.state.db.execute("INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?)",
                              ("T123", "C123", ROOT, "claude", "unknown-cwd-session", None))
        self.state.db.commit()
        self.client.pages = [{"messages": [event(thread_ts=ROOT)]}]
        self.runner.run.return_value = ("fresh", "answer")
        with patch.object(reply, "provider_for", return_value=self.runner) as factory:
            self.handle(event(thread_ts=ROOT))
        factory.assert_called_once_with("codex", self.path, self.path, model=None, effort=None)
        self.assertIsNone(self.runner.run.call_args.args[1])

    def test_missing_sticky_workspace_does_not_fall_back(self):
        missing = self.path / "removed"
        self.state.save_session("T123", "C123", ROOT, "codex", "old", missing)
        with patch.object(reply, "provider_for") as factory:
            with self.assertRaisesRegex(ValueError, "not a directory"):
                self.handle(event(thread_ts=ROOT))
        factory.assert_not_called()

    def test_thread_context_is_paginated_and_stops_at_trigger(self):
        trigger = event(ts=SECOND, thread_ts=ROOT)
        self.client.pages = [
            {"messages": [{"ts": ROOT, "user": "UOTHER", "text": "root"}],
             "response_metadata": {"next_cursor": "next"}},
            {"messages": [event(ts=FIRST, text="earlier"),
                          event(ts="1700000004.000001", text="later")],
             "response_metadata": {}},
        ]
        messages = reply.thread_messages(self.client, trigger)
        self.assertEqual([item["ts"] for item in messages], [ROOT, FIRST, SECOND])
        self.assertEqual(self.client.calls[1]["cursor"], "next")
        self.assertEqual(self.client.calls[0]["latest"], SECOND)

    def test_thread_resumes_and_own_answer_cannot_trigger(self):
        first = event(thread_ts=ROOT)
        second = event(ts=SECOND, text="bot again", thread_ts=ROOT)
        self.client.pages = [
            {"messages": [{"ts": ROOT, "user": "UOTHER", "text": "root"}],
             "response_metadata": {}},
            {"messages": [{"ts": ROOT, "user": "UOTHER", "text": "root"}, first],
             "response_metadata": {}},
        ]
        self.runner.run.side_effect = [("session-1", "answer 1"),
                                       ("session-1", "answer 2")]
        with patch.object(reply, "provider_for", return_value=self.runner):
            self.handle(first)
            self.handle(first)
            self.handle(event(ts="1700000003.000001", thread_ts=ROOT))
            self.handle(second)
        self.assertEqual(self.runner.run.call_count, 2)
        self.assertIsNone(self.runner.run.call_args_list[0].args[1])
        self.assertEqual(self.runner.run.call_args_list[1].args[1], "session-1")
        self.assertIn("root", self.runner.run.call_args_list[1].args[0])
        self.assertEqual(self.client.posts[0]["thread_ts"], ROOT)
        self.assertEqual(self.state.session("T123", "C123", ROOT), ("codex", "session-1", str(self.path)))

    def test_top_level_starts_thread_without_channel_history(self):
        self.runner.run.return_value = ("fresh", "answer")
        with patch.object(reply, "provider_for", return_value=self.runner):
            self.handle(event())
        self.assertEqual(self.client.calls, [])
        self.assertEqual(self.client.posts[0]["thread_ts"], FIRST)
        self.assertEqual(self.state.session("T123", "C123", FIRST), ("codex", "fresh", str(self.path)))
        self.assertIsNone(self.runner.run.call_args.args[1])
        self.assertNotIn("Thread through", self.runner.run.call_args.args[0])
        self.assertTrue(self.runner.run.call_args.args[0].endswith("question"))
        self.assertNotIn("bot question", self.runner.run.call_args.args[0])

    def test_followup_in_new_thread_resumes_top_level_session(self):
        root = event(ts=ROOT)
        followup = event(ts="1700000004.000001", text="bot follow up",
                         thread_ts=ROOT)
        self.client.pages = [{
            "messages": [root, {"ts": "1700000003.000001", "user": USER,
                                "text": "first answer"}, followup],
            "response_metadata": {},
        }]
        self.runner.run.side_effect = [("session-1", "first answer"),
                                       ("session-1", "second answer")]
        with patch.object(reply, "provider_for", return_value=self.runner):
            self.handle(root)
            self.handle(followup)
        self.assertIsNone(self.runner.run.call_args_list[0].args[1])
        self.assertEqual(self.runner.run.call_args_list[1].args[1], "session-1")
        self.assertIn("previous Slack Reply answer", self.runner.run.call_args_list[1].args[0])
        self.assertEqual([post["thread_ts"] for post in self.client.posts], [ROOT, ROOT])

    def test_provider_switch_starts_fresh_in_the_same_thread(self):
        self.state.save_session("T123", "C123", ROOT, "codex", "codex-session", self.path)
        os.environ["SLACK_REPLY_PROVIDER"] = "pi"
        requests = [event(ts=FIRST, text="claude review this", thread_ts=ROOT),
                    event(ts=SECOND, text="chat fix this", thread_ts=ROOT),
                    event(ts="1700000004.000001", text="bot verify this", thread_ts=ROOT)]
        self.client.pages = [{"messages": [request]} for request in requests]
        self.runner.run.side_effect = [("claude-session", "answer"),
                                       ("fresh-codex-session", "answer"), ("pi-session", "answer")]
        with patch.object(reply, "provider_for", return_value=self.runner) as factory:
            for request in requests:
                self.handle(request)
        self.assertEqual([call.args[0] for call in factory.call_args_list],
                         ["claude", "codex", "pi"])
        self.assertEqual([call.args[1] for call in self.runner.run.call_args_list], [None, None, None])
        self.assertEqual(self.state.session("T123", "C123", ROOT),
                         ("pi", "pi-session", str(self.path)))

    def test_session_survives_restart_in_private_state(self):
        self.state.save_session("T123", "C123", ROOT, "pi", "session-1", self.path)
        os.environ["SLACK_REPLY_PROVIDER"] = "pi"
        restarted = reply.State(self.path / "state")
        self.addCleanup(restarted.db.close)
        self.assertEqual(restarted.session("T123", "C123", ROOT),
                         ("pi", "session-1", str(self.path)))
        self.assertEqual((self.path / "state").stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.path / "state" / "sessions.sqlite3").stat().st_mode & 0o777, 0o600)

    def test_existing_codex_sessions_are_migrated(self):
        legacy_dir = self.path / "legacy"
        legacy_dir.mkdir()
        database = sqlite3.connect(legacy_dir / "sessions.sqlite3")
        database.execute("CREATE TABLE sessions (team TEXT, channel TEXT, thread_ts TEXT, "
                         "session_id TEXT, PRIMARY KEY (team, channel, thread_ts))")
        database.execute("INSERT INTO sessions VALUES (?, ?, ?, ?)",
                         ("T123", "C123", ROOT, "old-session"))
        database.commit()
        database.close()
        migrated = reply.State(legacy_dir)
        self.addCleanup(migrated.db.close)
        self.assertEqual(migrated.session("T123", "C123", ROOT),
                         ("codex", "old-session", None))

    def test_removed_provider_command_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "configure provider and model in .env"):
            reply.main(["provider", "pi"])

    def test_missing_provider_fails_before_slack_setup(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "SLACK_REPLY_PROVIDER"):
                reply.main([])

    def test_configured_provider_is_validated_before_slack_setup(self):
        with patch.dict(os.environ, {"SLACK_REPLY_PROVIDER": "pi"}, clear=True):
            with patch.object(reply, "require_available",
                              side_effect=RuntimeError("pi CLI is not installed")) as available:
                with self.assertRaisesRegex(RuntimeError, "pi CLI is not installed"):
                    reply.main([])
        available.assert_called_once_with("pi")


class ConfigurationTests(unittest.TestCase):
    def test_project_mapping_is_optional_and_resolves_directories(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(reply.project_workspaces(), {})
        with tempfile.TemporaryDirectory() as directory:
            import json
            with patch.dict(os.environ, {"SLACK_REPLY_PROJECTS": json.dumps({"work": directory})}):
                self.assertEqual(reply.project_workspaces(), {"work": Path(directory).resolve()})

    def test_invalid_project_config_is_rejected(self):
        for config in ['invalid json', '[]', 'null', '{"Bad": "/tmp"}',
                       '{"two words": "/tmp"}', '{"work": 3}', '{"work": ""}',
                       '{"work": "/nonexistent-slack-reply-project"}']:
            with self.subTest(config=config), patch.dict(os.environ, {"SLACK_REPLY_PROJECTS": config}):
                with self.assertRaises(ValueError):
                    reply.project_workspaces()


if __name__ == "__main__":
    unittest.main()
