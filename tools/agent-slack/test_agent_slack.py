import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import agent_slack as reply


USER = "U123ABC"
ROOT = "1700000000.000001"
FIRST = "1700000001.000001"
SECOND = "1700000002.000001"


def event(ts=FIRST, text="chat question", **extra):
    return {"type": "message", "user": USER, "channel": "C123", "ts": ts,
            "text": text, **extra}


class FakeClient:
    def __init__(self):
        self.pages = []
        self.calls = []
        self.posts = []
        self.reactions = []
        self.actions = []

    def reactions_add(self, **kwargs):
        self.reactions.append(("add", kwargs))
        self.actions.append(("reaction", "add", kwargs["name"]))

    def reactions_remove(self, **kwargs):
        self.reactions.append(("remove", kwargs))
        self.actions.append(("reaction", "remove", kwargs["name"]))

    def conversations_replies(self, **kwargs):
        self.calls.append(kwargs)
        return self.pages.pop(0)

    def chat_postMessage(self, **kwargs):
        self.posts.append(kwargs)
        self.actions.append(("post",))
        return {"ts": f"1700000003.{len(self.posts):06d}"}


class AgentSlackTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.state = reply.State(self.path / "state")
        self.addCleanup(self.state.db.close)
        self.client = FakeClient()
        self.runner = Mock()
        self.commands = {
            "chat": "codex",
            "claude": "claude",
            "assist": "pi",
        }
        self.projects = {"project": self.path / "project", "service": self.path / "service"}
        for directory in self.projects.values():
            directory.mkdir()

    def handle(self, message):
        if reply.acknowledge(message, "T123", USER, self.client, self.state, self.commands):
            reply.handle(message, "T123", USER, self.client, self.state, self.path, self.path, self.projects, self.commands)

    def test_reactions_mark_each_keyword_before_work_and_after_reply(self):
        for index, keyword in enumerate(self.commands):
            with self.subTest(keyword=keyword):
                self.client.reactions.clear()
                self.client.actions.clear()
                request = event(ts=f"1700000001.{index:06d}", text=f"{keyword} question", thread_ts=ROOT)
                self.client.pages = [{"messages": [request]}]

                def run(prompt, session_id):
                    self.assertEqual(self.client.reactions, [("add", {
                        "channel": "C123", "timestamp": request["ts"], "name": "eyes",
                    })])
                    self.client.actions.append(("run",))
                    return f"session-{keyword}", "answer"

                with patch.object(reply, "provider_for", return_value=Mock(run=run)):
                    self.handle(request)
                    self.handle(request)  # Completed deliveries must not restore :eyes:.
                self.assertEqual(self.client.actions, [
                    ("reaction", "add", "eyes"), ("run",), ("post",),
                    ("reaction", "add", "robot_face"),
                    ("reaction", "add", "white_check_mark"),
                    ("reaction", "remove", "eyes"),
                ])
                self.assertEqual(self.client.reactions[1][1]["timestamp"], f"1700000003.{index+1:06d}")
                for _, reaction in [self.client.reactions[0], *self.client.reactions[2:]]:
                    self.assertEqual(reaction["timestamp"], request["ts"])

    def test_failed_work_or_post_never_marks_the_request_completed(self):
        for stage in ("run", "post"):
            with self.subTest(stage=stage):
                self.client.actions.clear()
                self.client.reactions.clear()
                runner = Mock(run=Mock(side_effect=RuntimeError("CLI failed"))) if stage == "run" else self.runner
                self.runner.run.return_value = ("session", "answer")
                with patch.object(reply, "provider_for", return_value=runner):
                    with patch.object(self.client, "chat_postMessage", side_effect=RuntimeError("post failed")):
                        with self.assertRaises(RuntimeError):
                            self.handle(event())
                self.assertEqual([item[1]["name"] for item in self.client.reactions], ["eyes"])
                self.assertFalse(self.state.seen("handled", "T123", "C123", FIRST))

    def test_reaction_errors_do_not_block_or_repeat_the_reply(self):
        self.runner.run.return_value = ("session", "answer")
        with (patch.object(reply, "provider_for", return_value=self.runner),
              patch.object(self.client, "reactions_add", side_effect=RuntimeError("reaction unavailable")),
              patch.object(self.client, "reactions_remove", side_effect=RuntimeError("reaction unavailable")),
              patch("reactions.logging.Logger.warning") as warning):
            self.handle(event())
            self.handle(event())
        self.runner.run.assert_called_once()
        self.assertEqual(len(self.client.posts), 1)
        self.assertEqual(warning.call_count, 4)

    def test_duplicate_finishing_during_acknowledgement_does_not_restore_eyes(self):
        def add(**kwargs):
            self.state.mark_handled("T123", "C123", FIRST)

        with (patch.object(self.client, "reactions_add", side_effect=add),
              patch.object(reply, "provider_for") as factory):
            self.handle(event())
        factory.assert_not_called()
        self.assertEqual(self.client.reactions, [("remove", {
            "channel": "C123", "timestamp": FIRST, "name": "eyes",
        })])

    def test_repeated_or_missing_reactions_are_harmless(self):
        class APIError(Exception):
            def __init__(self, code):
                self.response = {"error": code}

        with (patch.object(self.client, "reactions_add", side_effect=APIError("already_reacted")),
              patch.object(self.client, "reactions_remove", side_effect=APIError("no_reaction")),
              patch("reactions.logging.Logger.warning") as warning):
            self.runner.run.return_value = ("session", "answer")
            with patch.object(reply, "provider_for", return_value=self.runner):
                self.handle(event())
        warning.assert_not_called()
        self.assertTrue(self.state.seen("handled", "T123", "C123", FIRST))

    def test_trigger_requires_same_author_and_exact_prefix(self):
        for text in ["assist question", "chat question", "claude question", "chat\tquestion", "chat\nquestion"]:
            self.assertTrue(reply.eligible(event(text=text), USER, self.commands))
        self.assertTrue(reply.eligible(event(subtype="thread_broadcast"), USER, self.commands))
        for overrides in [
            {"user": "UOTHER"}, {"bot_id": "B123"}, {"app_id": "A123"},
            {"subtype": "bot_message"}, {"subtype": "message_changed"},
            {"type": "app_mention"}, {"channel": ""}, {"ts": ""},
        ]:
            with self.subTest(overrides=overrides):
                self.assertFalse(reply.eligible(event(**overrides), USER, self.commands))
        for text in ["C question", "Bot question", " CHAT question", "please chat help", "chatbot help",
                     "claudecode help", f"question <@{USER}>", f"<@{USER}> chat question"]:
            with self.subTest(text=text):
                self.assertFalse(reply.eligible(event(text=text), USER, self.commands))

    def test_unauthorized_users_and_mentions_never_run_provider(self):
        with patch.object(reply, "provider_for") as factory:
            for keyword in self.commands:
                self.handle(event(text=f"{keyword} project do this", user="UOTHER"))
            self.handle(event(text="bot project do this"))
            self.handle(event(text=f"question <@{USER}>"))
            self.handle(event(text=f"<@{USER}> C question"))
        factory.assert_not_called()
        self.assertEqual(self.client.posts, [])
        self.assertEqual(self.client.calls, [])
        self.assertEqual(self.client.reactions, [])

    def test_empty_commands_are_ignored(self):
        with patch.object(reply, "provider_for") as factory:
            for text in ["chat", "chat ", "assist   ", "claude\n"]:
                with self.subTest(text=text):
                    self.assertIsNone(reply.command(text, self.projects, self.commands))
                    self.handle(event(text=text))
        factory.assert_not_called()
        self.assertEqual(self.client.reactions, [])

    def test_prefix_selects_provider_before_matching_workspace(self):
        for index, keyword in enumerate(self.commands):
            with self.subTest(keyword=keyword):
                self.runner.run.return_value = (f"session-{index}", "answer")
                with patch.object(reply, "provider_for", return_value=self.runner) as factory:
                    self.handle(event(ts=f"1700000001.{index:06d}", text=f"{keyword} explain the PROJECT build"))
                factory.assert_called_once_with(self.commands[keyword], self.projects["project"], self.path)
                self.assertTrue(self.runner.run.call_args.args[0].endswith("explain the PROJECT build"))

    def test_first_mentioned_workspace_runs_once_with_the_full_request(self):
        request = event(text="chat compare service and project")
        self.runner.run.return_value = ("service-session", "answer")
        with patch.object(reply, "provider_for", return_value=self.runner) as factory:
            self.handle(request)
            self.handle(request)
        factory.assert_called_once_with(self.commands["chat"], self.projects["service"], self.path)
        self.runner.run.assert_called_once()
        self.assertTrue(self.runner.run.call_args.args[0].endswith("compare service and project"))
        self.assertEqual(len(self.client.posts), 1)
        self.assertEqual(self.client.posts[0]["markdown_text"], "answer")

    def test_keywords_for_one_provider_resume_the_same_session(self):
        self.commands["quick"] = "codex"
        root = event(ts=ROOT, text="chat first question")
        followup = event(text="quick follow up", thread_ts=ROOT)
        self.client.pages = [{"messages": [root, followup]}]
        self.runner.run.return_value = ("session-1", "answer")
        with patch.object(reply, "provider_for", return_value=self.runner) as factory:
            self.handle(root)
            self.handle(followup)
        self.assertEqual([call.args[0] for call in factory.call_args_list],
                         [self.commands["chat"], self.commands["quick"]])
        self.assertEqual([call.args[1] for call in self.runner.run.call_args_list], [None, "session-1"])

    def test_alias_workspace_sticks_without_alias_and_survives_restart(self):
        self.runner.run.side_effect = [("project-session", "answer"),
                                       ("project-session", "followup answer")]
        root = event(ts=ROOT, text="chat project first question")
        followup = event(text="chat follow up", thread_ts=ROOT)
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
                                self.projects["project"], ROOT)
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
                                self.projects["project"], ROOT)
        self.client.pages = [{"messages": [event(thread_ts=ROOT)]}]
        self.runner.run.return_value = ("same-session", "answer")
        with patch.object(reply, "provider_for", return_value=self.runner):
            self.handle(event(text="chat project continue", thread_ts=ROOT))
        self.assertEqual(self.runner.run.call_args.args[1], "same-session")

    def test_missing_sticky_workspace_does_not_fall_back(self):
        missing = self.path / "removed"
        self.state.save_session("T123", "C123", ROOT, "codex", "old", missing, ROOT)
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

    def test_first_thread_invocation_includes_prior_context_and_one_stripped_request(self):
        old_answer = "1700000001.500000"
        self.state.record_reply("T123", "C123", old_answer, "claude", "another-session")
        trigger = event(ts=SECOND, text="chat explain project", thread_ts=ROOT)
        self.client.pages = [{"messages": [
            {"ts": ROOT, "user": "UOTHER", "text": "original discussion"},
            event(text="chat earlier request"),
            event(ts=old_answer, text="earlier AI answer"), trigger,
        ]}]
        self.runner.run.return_value = ("fresh-session", "answer")
        with patch.object(reply, "provider_for", return_value=self.runner):
            self.handle(trigger)
        prompt, session = self.runner.run.call_args.args
        self.assertIsNone(session)
        self.assertIn("original discussion", prompt)
        self.assertIn("chat earlier request", prompt)
        self.assertIn("earlier AI answer", prompt)
        self.assertIn("previous Agent Slack answer", prompt)
        self.assertEqual(prompt.count("explain project"), 1)
        self.assertNotIn("chat explain project", prompt)
        self.assertNotIn("oldest", self.client.calls[0])

    def test_resume_sends_only_new_messages_and_skips_its_answer_after_restart(self):
        root = {"ts": ROOT, "user": "UOTHER", "text": "old root discussion"}
        first = event(text="chat first request", thread_ts=ROOT)
        second = event(ts="1700000004.000001", text="chat follow up", thread_ts=ROOT)
        self.client.pages = [{"messages": [root, first]}, {"messages": [
            root, first,
            event(ts="1700000001.500001", text="shared words", user="UOTHER"),
            event(ts="1700000003.000001", text="shared words"),  # Our first AI reply.
            event(ts="1700000003.500001", text="shared words"),  # Same text, new human message.
            event(ts="1700000005.000001", text="future discussion"), second,
        ]}]
        self.runner.run.side_effect = [("session-1", "shared words"), ("session-1", "answer")]
        with patch.object(reply, "provider_for", return_value=self.runner):
            self.handle(first)
            self.state.db.close()
            self.state = reply.State(self.path / "state")
            self.addCleanup(self.state.db.close)
            self.handle(second)
        prompt, session = self.runner.run.call_args.args
        self.assertEqual(session, "session-1")
        self.assertEqual(self.client.calls[1]["oldest"], FIRST)
        self.assertEqual(self.client.calls[1]["latest"], second["ts"])
        self.assertNotIn("old root discussion", prompt)
        self.assertNotIn("first request", prompt)
        self.assertNotIn("future discussion", prompt)
        self.assertEqual(prompt.count("shared words"), 2)
        self.assertEqual(prompt.count("follow up"), 1)
        self.assertNotIn("chat follow up", prompt)
        self.assertEqual(self.state.session("T123", "C123", ROOT)[3], second["ts"])

    def test_resume_includes_new_ai_replies_from_a_different_provider_session(self):
        self.state.save_session("T123", "C123", ROOT, "codex", "session-1", self.path, FIRST)
        other_answer, own_answer = "1700000001.100001", "1700000001.200001"
        self.state.record_reply("T123", "C123", other_answer, "claude", "session-1")
        self.state.record_reply("T123", "C123", own_answer, "codex", "session-1")
        trigger = event(ts=SECOND, text="chat continue", thread_ts=ROOT)
        self.client.pages = [{"messages": [
            event(ts=other_answer, text="other session answer"),
            event(ts=own_answer, text="already known answer"), trigger,
        ]}]
        self.runner.run.return_value = ("session-1", "answer")
        with patch.object(reply, "provider_for", return_value=self.runner):
            self.handle(trigger)
        prompt, session = self.runner.run.call_args.args
        self.assertEqual(session, "session-1")
        self.assertIn("other session answer", prompt)
        self.assertNotIn("already known answer", prompt)

    def test_provider_or_workspace_switch_gets_full_context_again(self):
        old_answer = "1700000003.900001"
        self.state.record_reply("T123", "C123", old_answer, "codex", "old-session")
        for index, request in enumerate(["claude continue", "chat service continue"]):
            with self.subTest(request=request):
                self.state.save_session("T123", "C123", ROOT, "codex", "old-session",
                                        self.projects["project"], FIRST)
                trigger = event(ts=f"170000000{index+4}.000001", text=request, thread_ts=ROOT)
                self.client.pages = [{"messages": [
                    {"ts": ROOT, "user": "UOTHER", "text": "old root discussion"},
                    event(ts=old_answer, text="previous session answer"), trigger,
                ]}]
                self.runner.run.return_value = (f"fresh-{index}", "answer")
                with patch.object(reply, "provider_for", return_value=self.runner):
                    self.handle(trigger)
                prompt, session = self.runner.run.call_args.args
                self.assertIsNone(session)
                self.assertIn("old root discussion", prompt)
                self.assertIn("previous session answer", prompt)
                self.assertNotIn("oldest", self.client.calls[-1])

    def test_failed_provider_does_not_advance_the_context_timestamp(self):
        self.state.save_session("T123", "C123", ROOT, "codex", "session-1", self.path, FIRST)
        trigger = event(ts=SECOND, text="chat continue", thread_ts=ROOT)
        self.client.pages = [{"messages": [trigger]}]
        self.runner.run.side_effect = RuntimeError("provider failed")
        with patch.object(reply, "provider_for", return_value=self.runner):
            with self.assertRaisesRegex(RuntimeError, "provider failed"):
                self.handle(trigger)
        self.assertEqual(self.state.session("T123", "C123", ROOT)[3], FIRST)

    def test_thread_resumes_and_own_answer_cannot_trigger(self):
        first = event(thread_ts=ROOT)
        second = event(ts=SECOND, text="chat again", thread_ts=ROOT)
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
        self.assertNotIn("root", self.runner.run.call_args_list[1].args[0])
        self.assertEqual(self.client.posts[0]["thread_ts"], ROOT)
        self.assertEqual(self.state.session("T123", "C123", ROOT), ("codex", "session-1", str(self.path), SECOND))

    def test_top_level_starts_thread_without_channel_history(self):
        self.runner.run.return_value = ("fresh", "answer")
        with patch.object(reply, "provider_for", return_value=self.runner):
            self.handle(event())
        self.assertEqual(self.client.calls, [])
        self.assertEqual(self.client.posts[0]["thread_ts"], FIRST)
        self.assertEqual(self.state.session("T123", "C123", FIRST), ("codex", "fresh", str(self.path), FIRST))
        self.assertIsNone(self.runner.run.call_args.args[1])
        self.assertNotIn("Thread through", self.runner.run.call_args.args[0])
        self.assertTrue(self.runner.run.call_args.args[0].endswith("question"))
        self.assertNotIn("chat question", self.runner.run.call_args.args[0])

    def test_followup_in_new_thread_resumes_top_level_session(self):
        root = event(ts=ROOT)
        followup = event(ts="1700000004.000001", text="chat follow up",
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
        self.assertNotIn("first answer", self.runner.run.call_args_list[1].args[0])
        self.assertNotIn("previous Agent Slack answer", self.runner.run.call_args_list[1].args[0])
        self.assertNotIn("question", self.runner.run.call_args_list[1].args[0])
        self.assertEqual([post["thread_ts"] for post in self.client.posts], [ROOT, ROOT])

    def test_provider_switch_starts_fresh_in_the_same_thread(self):
        self.state.save_session("T123", "C123", ROOT, "codex", "codex-session", self.path, ROOT)
        requests = [event(ts=FIRST, text="claude review this", thread_ts=ROOT),
                    event(ts=SECOND, text="chat fix this", thread_ts=ROOT),
                    event(ts="1700000004.000001", text="assist verify this", thread_ts=ROOT)]
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
                         ("pi", "pi-session", str(self.path), "1700000004.000001"))

    def test_session_survives_restart_in_private_state(self):
        self.state.save_session("T123", "C123", ROOT, "pi", "session-1", self.path, ROOT)
        restarted = reply.State(self.path / "state")
        self.addCleanup(restarted.db.close)
        self.assertEqual(restarted.session("T123", "C123", ROOT),
                         ("pi", "session-1", str(self.path), ROOT))
        self.assertEqual((self.path / "state").stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.path / "state" / "sessions.sqlite3").stat().st_mode & 0o777, 0o600)

    def test_removed_provider_command_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "configure keyword commands in .env"):
            reply.main(["provider", "pi"])

    def test_missing_command_configuration_fails_before_slack_setup(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "AGENT_SLACK_COMMANDS"):
                reply.main([])

    def test_configured_provider_is_validated_before_slack_setup(self):
        with patch.dict(os.environ, {"AGENT_SLACK_COMMANDS": '{"work":"pi"}'}, clear=True):
            with patch.object(reply, "require_available", side_effect=RuntimeError("pi CLI is not installed")) as available:
                with self.assertRaisesRegex(RuntimeError, "pi CLI is not installed"):
                    reply.main([])
        available.assert_called_once_with("pi")

class ConfigurationTests(unittest.TestCase):
    def test_project_mapping_is_optional_and_resolves_directories(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(reply.project_workspaces(), {})
        with tempfile.TemporaryDirectory() as directory:
            import json
            with patch.dict(os.environ, {"AGENT_SLACK_PROJECTS": json.dumps({"work": directory})}):
                self.assertEqual(reply.project_workspaces(), {"work": Path(directory).resolve()})

    def test_invalid_project_config_is_rejected(self):
        for config in ['invalid json', '[]', 'null', '{"Bad": "/tmp"}',
                       '{"two words": "/tmp"}', '{"work": 3}', '{"work": ""}',
                       '{"work": "/nonexistent-agent-slack-project"}']:
            with self.subTest(config=config), patch.dict(os.environ, {"AGENT_SLACK_PROJECTS": config}):
                with self.assertRaises(ValueError):
                    reply.project_workspaces()


if __name__ == "__main__":
    unittest.main()
