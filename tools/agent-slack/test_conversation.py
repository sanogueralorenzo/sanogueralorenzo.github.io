import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, call, patch

import conversation as reply
from commands import Command


USER = "U123"
ROOT = "1700000000.000001"
FIRST = "1700000001.000001"
SECOND = "1700000002.000001"
ANSWER = "1700000003.000001"


def event(ts=FIRST, text="chat question", **extra):
    return {"type": "message", "user": USER, "channel": "C123", "ts": ts,
            "text": text, **extra}


class ConversationTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name)
        self.state = reply.State(self.path / "state")
        self.addCleanup(self.state.db.close)
        self.commands = {
            "chat": Command(("tool",), ("tool", "{session_id}")),
            "review": Command(("other",), ("other", "{session_id}")),
        }
        self.commands["assist"] = self.commands["chat"]
        self.projects = {name: self.path / name for name in ("project", "service")}
        for path in self.projects.values():
            path.mkdir()
        self.client = Mock()
        self.client.chat_postMessage.return_value = {"ts": ANSWER}
        self.runner = Mock()
        self.runner.run.return_value = ("session-1", "chat answer")
        executor = patch.object(reply, "Executor", return_value=self.runner)
        self.executor = executor.start()
        self.addCleanup(executor.stop)

    def handle(self, message):
        parsed = reply.acknowledge(message, "T123", USER, self.client, self.state, self.projects, self.commands)
        if parsed is not None:
            reply.handle(message, parsed, "T123", self.client, self.state, self.path)

    def test_top_level_request_posts_once_with_progress_and_ignores_its_own_answer(self):
        request = event()
        self.handle(request)
        self.handle(request)  # Duplicate event delivery.
        self.handle(event(ts=ANSWER, text="chat answer"))  # Reply is posted as the same user.
        self.executor.assert_called_once_with(self.commands["chat"], self.path)
        prompt, session = self.runner.run.call_args.args
        self.assertIsNone(session)
        self.assertTrue(prompt.endswith("question"))
        self.assertNotIn("chat question", prompt)
        self.client.conversations_replies.assert_not_called()
        self.assertEqual(self.client.method_calls, [
            call.reactions_add(channel="C123", timestamp=FIRST, name="eyes"),
            call.chat_postMessage(channel="C123", thread_ts=FIRST, markdown_text="chat answer",
                                  unfurl_links=False, unfurl_media=False),
            call.reactions_add(channel="C123", timestamp=ANSWER, name="robot_face"),
            call.reactions_add(channel="C123", timestamp=FIRST, name="white_check_mark"),
            call.reactions_remove(channel="C123", timestamp=FIRST, name="eyes"),
        ])

    def test_failures_clear_eyes_without_posting_an_error(self):
        for stage in ("history", "run", "post"):
            with self.subTest(stage=stage):
                self.state.save_session("T123", "C123", ROOT, self.commands["chat"].key,
                                        "session-1", self.path, FIRST)
                self.client.reset_mock(side_effect=True)
                self.runner.run.reset_mock(side_effect=True)
                self.client.conversations_replies.return_value = {"messages": []}
                failing = {"history": self.client.conversations_replies, "run": self.runner.run,
                           "post": self.client.chat_postMessage}[stage]
                failing.side_effect = RuntimeError(f"{stage} failed")
                with self.assertRaisesRegex(RuntimeError, f"{stage} failed"):
                    self.handle(event(ts=SECOND, thread_ts=ROOT))
                self.client.reactions_add.assert_called_once_with(channel="C123", timestamp=SECOND, name="eyes")
                self.client.reactions_remove.assert_called_once_with(channel="C123", timestamp=SECOND, name="eyes")
                self.assertFalse(self.state.seen("handled", "T123", "C123", SECOND))
                if stage != "post":
                    self.client.chat_postMessage.assert_not_called()
                    self.assertEqual(self.state.session("T123", "C123", ROOT)[3], FIRST)

    def test_reaction_errors_do_not_block_or_duplicate_answers(self):
        self.client.reactions_add.side_effect = RuntimeError("unavailable")
        self.client.reactions_remove.side_effect = RuntimeError("unavailable")
        with patch("reactions.logging.Logger.warning"):
            self.handle(event())
            self.handle(event())
        self.runner.run.assert_called_once()
        self.client.chat_postMessage.assert_called_once()

    def test_duplicate_finishing_during_acknowledgement_does_not_restore_eyes(self):
        self.client.reactions_add.side_effect = lambda **kwargs: self.state.mark_handled("T123", "C123", FIRST)
        self.handle(event())
        self.runner.run.assert_not_called()
        self.client.reactions_remove.assert_called_once_with(channel="C123", timestamp=FIRST, name="eyes")

    def test_first_thread_invocation_fetches_full_context_up_to_the_request(self):
        old_answer = "1700000001.500001"
        self.state.record_reply("T123", "C123", old_answer, self.commands["review"].key, "old")
        self.client.conversations_replies.side_effect = [
            {"messages": [event(ts=ROOT, text="original discussion", user="UOTHER")],
             "response_metadata": {"next_cursor": "next"}},
            {"messages": [event(text="chat earlier request"), event(ts=old_answer, text="old AI answer"),
                          event(ts=ANSWER, text="future message")]},
        ]
        self.handle(event(ts=SECOND, text="chat explain project", thread_ts=ROOT))
        prompt, session = self.runner.run.call_args.args
        self.assertIsNone(session)
        for text in ("original discussion", "chat earlier request", "old AI answer", "previous Agent Slack answer"):
            self.assertIn(text, prompt)
        self.assertNotIn("future message", prompt)
        self.assertEqual(prompt.count("explain project"), 1)
        self.assertNotIn("chat explain project", prompt)
        self.assertEqual(self.client.conversations_replies.call_args.kwargs["cursor"], "next")
        self.assertEqual(self.client.conversations_replies.call_args.kwargs["latest"], SECOND)
        self.assertNotIn("oldest", self.client.conversations_replies.call_args.kwargs)

    def test_resume_after_restart_keeps_workspace_and_sends_only_new_context(self):
        root = event(ts=ROOT, text="chat project first request")
        self.runner.run.return_value = ("session-1", "shared words")
        self.handle(root)
        self.state.record_reply("T123", "C123", "1700000003.100001", self.commands["review"].key, "session-1")
        self.state.record_reply("T123", "C123", "1700000003.200001", self.commands["chat"].key, "other-session")
        self.state.db.close()
        self.state = reply.State(self.path / "state")
        self.addCleanup(self.state.db.close)
        self.assertEqual((self.path / "state").stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.path / "state" / "sessions.sqlite3").stat().st_mode & 0o777, 0o600)
        followup = event(ts="1700000004.000001", text="assist follow up", thread_ts=ROOT)
        self.client.conversations_replies.return_value = {"messages": [
            root,
            event(text="shared words", user="UOTHER"),  # Arrived while the first request ran.
            event(ts=ANSWER, text="shared words"),  # Already known to this session.
            event(ts="1700000003.100001", text="other command answer"),
            event(ts="1700000003.200001", text="other session answer"),
            event(ts="1700000003.500001", text="shared words"),  # Same text, human message.
            followup, event(ts="1700000005.000001", text="future message"),
        ]}
        self.client.chat_postMessage.return_value = {"ts": "1700000006.000001"}
        self.handle(followup)
        self.executor.assert_called_with(self.commands["assist"], self.projects["project"])
        prompt, session = self.runner.run.call_args.args
        self.assertEqual(session, "session-1")
        self.assertEqual(prompt.count("shared words"), 2)
        self.assertIn("other command answer", prompt)
        self.assertIn("other session answer", prompt)
        for text in ("first request", "future message", "assist follow up"):
            self.assertNotIn(text, prompt)
        self.assertEqual(prompt.count("follow up"), 1)
        self.assertEqual(self.client.conversations_replies.call_args.kwargs["oldest"], ROOT)
        self.assertEqual(self.state.session("T123", "C123", ROOT)[3], followup["ts"])

    def test_changing_commands_or_workspace_starts_fresh_with_full_context(self):
        for index, text in enumerate(("review continue", "chat service continue", "assist continue")):
            with self.subTest(text=text):
                self.state.save_session("T123", "C123", ROOT, self.commands["chat"].key,
                                        "old-session", self.projects["project"], FIRST)
                if text.startswith("assist"):
                    self.commands["assist"] = Command(("tool", "changed"), ("tool", "{session_id}"))
                self.client.conversations_replies.return_value = {"messages": [event(ts=ROOT, text="old discussion")]}
                self.client.chat_postMessage.return_value = {"ts": f"1700000006.{index:06d}"}
                self.handle(event(ts=f"1700000004.{index:06d}", text=text, thread_ts=ROOT))
                prompt, session = self.runner.run.call_args.args
                self.assertIsNone(session)
                self.assertIn("old discussion", prompt)
                self.assertNotIn("oldest", self.client.conversations_replies.call_args.kwargs)

    def test_removed_workspace_does_not_silently_fall_back(self):
        self.state.save_session("T123", "C123", ROOT, self.commands["chat"].key,
                                "session-1", self.path / "removed", ROOT)
        with self.assertRaisesRegex(ValueError, "not a directory"):
            self.handle(event(thread_ts=ROOT))
        self.runner.run.assert_not_called()
        self.client.reactions_remove.assert_called_once_with(channel="C123", timestamp=FIRST, name="eyes")


if __name__ == "__main__":
    unittest.main()
