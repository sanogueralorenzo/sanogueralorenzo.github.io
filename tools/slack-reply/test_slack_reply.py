import contextlib
import io
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


def event(ts=FIRST, text=f"question <@{USER}>", **extra):
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

    def handle(self, message):
        reply.handle(message, "T123", USER, self.client, self.state, self.path, self.path)

    def test_trigger_requires_same_author_and_explicit_self_mention(self):
        self.assertTrue(reply.eligible(event(), USER))
        self.assertFalse(reply.eligible(event(user="UOTHER"), USER))
        self.assertFalse(reply.eligible(event(text="question @me"), USER))
        self.assertFalse(reply.eligible(event(text="question <@U123ABCD>"), USER))
        self.assertFalse(reply.eligible(event(bot_id="B123"), USER))
        self.assertFalse(reply.eligible(event(subtype="bot_message"), USER))
        self.assertTrue(reply.eligible(event(subtype="thread_broadcast"), USER))

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
        second = event(ts=SECOND, text=f"again <@{USER}>", thread_ts=ROOT)
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
        self.assertEqual(self.state.session("T123", "C123", ROOT), ("codex", "session-1"))

    def test_top_level_starts_thread_without_channel_history(self):
        self.runner.run.return_value = ("fresh", "answer")
        with patch.object(reply, "provider_for", return_value=self.runner):
            self.handle(event())
        self.assertEqual(self.client.calls, [])
        self.assertEqual(self.client.posts[0]["thread_ts"], FIRST)
        self.assertEqual(self.state.session("T123", "C123", FIRST), ("codex", "fresh"))
        self.assertIsNone(self.runner.run.call_args.args[1])
        self.assertNotIn("Thread through", self.runner.run.call_args.args[0])

    def test_followup_in_new_thread_resumes_top_level_session(self):
        root = event(ts=ROOT)
        followup = event(ts="1700000004.000001", text=f"follow up <@{USER}>",
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

    def test_provider_change_applies_to_new_threads_but_pins_existing_sessions(self):
        self.state.save_session("T123", "C123", ROOT, "codex", "codex-session")
        self.state.set_provider("claude")
        self.client.pages = [{"messages": [event(ts=ROOT), event(ts=FIRST, thread_ts=ROOT)],
                              "response_metadata": {}}]
        self.runner.run.side_effect = [("codex-session", "old answer"),
                                       ("claude-session", "new answer")]
        with patch.object(reply, "provider_for", return_value=self.runner) as factory:
            self.handle(event(ts=FIRST, thread_ts=ROOT))
            self.handle(event(ts=SECOND))
        self.assertEqual([call.args[0] for call in factory.call_args_list],
                         ["codex", "claude"])
        self.assertEqual(self.state.session("T123", "C123", SECOND),
                         ("claude", "claude-session"))

    def test_session_and_preference_survive_restart_in_private_state(self):
        self.state.save_session("T123", "C123", ROOT, "claude", "session-1")
        self.state.set_provider("claude")
        restarted = reply.State(self.path / "state")
        self.addCleanup(restarted.db.close)
        self.assertEqual(restarted.session("T123", "C123", ROOT),
                         ("claude", "session-1"))
        self.assertEqual(restarted.provider(), "claude")
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
                         ("codex", "old-session"))

    def test_provider_command_rejects_missing_cli_without_changing_preference(self):
        with patch.dict(os.environ, {"SLACK_REPLY_STATE_DIR": str(self.path / "state")}):
            with patch.object(reply, "require_available",
                              side_effect=RuntimeError("claude CLI is not installed")):
                with self.assertRaisesRegex(RuntimeError, "not installed"):
                    reply.main(["provider", "claude"])
        self.assertEqual(self.state.provider(), "codex")

    def test_provider_command_saves_available_cli_without_slack_credentials(self):
        with patch.dict(os.environ, {"SLACK_REPLY_STATE_DIR": str(self.path / "state")},
                        clear=True):
            with patch.object(reply, "require_available"):
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    reply.main(["provider", "claude"])
        self.assertEqual(self.state.provider(), "claude")
        self.assertEqual(output.getvalue(), "claude\n")


if __name__ == "__main__":
    unittest.main()
