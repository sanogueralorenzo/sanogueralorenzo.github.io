import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

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
        self.client = FakeClient()

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
        with patch.object(reply, "run_codex", side_effect=[("session-1", "answer 1"),
                                                         ("session-1", "answer 2")]) as codex:
            reply.handle(first, "T123", USER, self.client, self.state,
                         self.path, "gpt-6-luna", "medium", self.path)
            reply.handle(first, "T123", USER, self.client, self.state,
                         self.path, "gpt-6-luna", "medium", self.path)
            own = event(ts="1700000003.000001", thread_ts=ROOT)
            reply.handle(own, "T123", USER, self.client, self.state,
                         self.path, "gpt-6-luna", "medium", self.path)
            reply.handle(second, "T123", USER, self.client, self.state,
                         self.path, "gpt-6-luna", "medium", self.path)
        self.assertEqual(codex.call_count, 2)
        self.assertIsNone(codex.call_args_list[0].args[1])
        self.assertEqual(codex.call_args_list[1].args[1], "session-1")
        self.assertIn("root", codex.call_args_list[1].args[0])
        self.assertEqual(self.client.posts[0]["thread_ts"], ROOT)
        self.assertEqual(self.state.session("T123", "C123", ROOT), "session-1")

    def test_top_level_has_no_history_or_session(self):
        with patch.object(reply, "run_codex", return_value=("fresh", "answer")) as codex:
            reply.handle(event(), "T123", USER, self.client, self.state,
                         self.path, "gpt-6-luna", "low", self.path)
        self.assertEqual(self.client.calls, [])
        self.assertNotIn("thread_ts", self.client.posts[0])
        self.assertIsNone(codex.call_args.args[1])
        self.assertNotIn("Thread through", codex.call_args.args[0])

    def test_session_survives_restart_in_private_state(self):
        self.state.save_session("T123", "C123", ROOT, "session-1")
        restarted = reply.State(self.path / "state")
        self.assertEqual(restarted.session("T123", "C123", ROOT), "session-1")
        self.assertEqual((self.path / "state").stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.path / "state" / "sessions.sqlite3").stat().st_mode & 0o777, 0o600)

    def test_codex_uses_resume_and_drops_slack_tokens(self):
        def fake_run(command, **kwargs):
            Path(command[command.index("-o") + 1]).write_text("final answer")
            self.assertNotIn("SLACK_USER_TOKEN", kwargs["env"])
            self.assertEqual(command[:3], ["codex", "exec", "resume"])
            self.assertEqual(command[-2:], ["session-1", "-"])
            return type("Result", (), {
                "returncode": 0,
                "stdout": '{"type":"thread.started","thread_id":"session-1"}\n',
                "stderr": "",
            })()

        with patch.dict(os.environ, {"SLACK_USER_TOKEN": "secret"}):
            with patch.object(reply.subprocess, "run", side_effect=fake_run):
                session, answer = reply.run_codex(
                    "prompt", "session-1", self.path, "gpt-6-luna", "high", self.path,
                )
        self.assertEqual((session, answer), ("session-1", "final answer"))

    def test_new_codex_session_id_comes_from_json_events(self):
        def fake_run(command, **kwargs):
            Path(command[command.index("-o") + 1]).write_text("new answer")
            self.assertIn("-C", command)
            return type("Result", (), {
                "returncode": 0,
                "stdout": '{"type":"thread.started","thread_id":"new-session"}\n'
                          '{"type":"turn.completed"}\n',
                "stderr": "",
            })()

        with patch.object(reply.subprocess, "run", side_effect=fake_run):
            session, answer = reply.run_codex(
                "prompt", None, self.path, "gpt-6-luna", "medium", self.path,
            )
        self.assertEqual((session, answer), ("new-session", "new answer"))

    def test_resume_rejects_a_different_session_id(self):
        def fake_run(command, **kwargs):
            Path(command[command.index("-o") + 1]).write_text("answer")
            return type("Result", (), {
                "returncode": 0,
                "stdout": '{"type":"thread.started","thread_id":"other-session"}\n',
                "stderr": "",
            })()

        with patch.object(reply.subprocess, "run", side_effect=fake_run):
            with self.assertRaisesRegex(RuntimeError, "different session"):
                reply.run_codex("prompt", "session-1", self.path,
                                "gpt-6-luna", "high", self.path)


if __name__ == "__main__":
    unittest.main()
