import io
import os
import queue
import signal
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from threading import Event, Lock
from types import SimpleNamespace
from unittest.mock import Mock, patch

from agent_slack import app, cli
from agent_slack.commands import Command
from agent_slack.state import State


class BridgeTests(unittest.TestCase):
    def test_socket_events_run_parallel_threads_and_resume_queued_followups(self):
        events = [
            {"type": "message", "user": "U123", "channel": "C123", "ts": ts,
             "text": f"work {text}", **extra}
            for ts, text, extra in (("1700000001.000001", "first", {}),
                                    ("1700000001.000001", "first", {}),  # Duplicate delivery.
                                    ("1700000002.000001", "followup", {"thread_ts": "1700000001.000001"}),
                                    ("1700000003.000001", "independent", {}))
        ]
        independent, delivered = Event(), Event()
        lock, calls, posts = Lock(), [], []
        inbox = queue.Queue()
        client = Mock()
        client.auth_test.return_value = {"team_id": "T123", "user_id": "U123"}
        client.conversations_replies.side_effect = lambda **kwargs: {"messages": events[:3]}
        command = Command(("custom",), ("custom", "{session_id}"))

        def run(selected, prompt, workspace, session_id):
            self.assertEqual(selected, command)
            name = prompt.split()[-1]
            calls.append((name, session_id))
            if name == "first":
                if not independent.wait(5):
                    raise RuntimeError("Another Slack thread was blocked")
            elif name == "independent":
                client.reactions_add.assert_any_call(channel="C123", timestamp=events[2]["ts"], name="eyes")
                self.assertNotIn(("followup", "session-first"), calls)
                independent.set()
            return session_id or f"session-{name}", f"answer {name}"

        def post(**kwargs):
            with lock:
                posts.append(kwargs)
                if len(posts) == 3:
                    delivered.set()
                return {"ts": f"1700000004.{len(posts):06d}"}

        def next_event():
            try:
                return inbox.get_nowait()
            except queue.Empty:
                self.assertTrue(delivered.wait(5), "The bridge did not finish its requests")
                signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)

        socket = Mock(socket_mode_request_listeners=[])

        def connect():
            foreign = {**events[0], "ts": "1700000005.000001", "text": "work foreign"}
            for index, event in enumerate([*events, foreign]):
                request = SimpleNamespace(type="events_api", envelope_id=str(index),
                                          payload={"team_id": "T123" if index < 4 else "FOREIGN", "event": event})
                socket.socket_mode_request_listeners[0](socket, request)

        socket.connect.side_effect = connect
        client.chat_postMessage.side_effect = post
        with tempfile.TemporaryDirectory() as directory:
            env = {"SLACK_APP_TOKEN": "xapp-test", "SLACK_USER_TOKEN": "xoxp-test", "SLACK_USER_ID": "U123",
                   "AGENT_SLACK_WORKSPACE": directory, "AGENT_SLACK_PROJECTS": "{}", "AGENT_SLACK_STATE_DIR": directory}
            with (patch.dict(os.environ, env, clear=True),
                  patch.object(app, "load_commands", return_value={"work": command}),
                  patch.object(app, "WebClient", return_value=client),
                  patch.object(app, "SocketModeClient", return_value=socket),
                  patch.object(app.queue, "Queue", return_value=SimpleNamespace(put=inbox.put, get=next_event)),
                  patch.object(app, "ProcessRunner", return_value=Mock(closed=False)) as process_factory,
                  patch.object(app, "Executor", return_value=Mock(run=run)),
                  patch("agent_slack.thread_queue.logging.Logger.exception") as errors,
                  redirect_stdout(io.StringIO())):
                previous_signal = signal.getsignal(signal.SIGTERM)
                with self.assertRaises(KeyboardInterrupt):
                    cli.run(["--config", str(Path(directory) / ".env")])
                self.assertEqual(signal.getsignal(signal.SIGTERM), previous_signal)
                process_factory.return_value.close.assert_called_once()
                errors.assert_not_called()
            state = State(Path(directory))
            try:
                session = state.session("T123", "C123", events[0]["ts"])
                self.assertEqual(session.command_key, command.key)
                self.assertEqual(session.session_id, "session-first")
            finally:
                state.close()
        self.assertCountEqual(calls, [("first", None), ("independent", None), ("followup", "session-first")])
        self.assertEqual(len(posts), 3)
        self.assertEqual(socket.send_socket_mode_response.call_count, 5)
        socket.close.assert_called_once()

    def test_failed_connection_closes_resources_and_next_app_gets_a_fresh_runner(self):
        client = Mock()
        client.auth_test.return_value = {"team_id": "T123", "user_id": "U123"}
        runners = []
        previous_signal = signal.getsignal(signal.SIGTERM)
        with tempfile.TemporaryDirectory() as directory:
            config = app.Config(app_token="xapp-test", user_token="xoxp-test", user_id="U123",
                                workspace=Path(directory), state_dir=Path(directory), commands={}, projects={})
            for _ in range(2):
                socket = Mock(socket_mode_request_listeners=[])

                def fail_connection():
                    self.assertFalse(bridge.processes.closed)
                    runners.append(bridge.processes)
                    raise RuntimeError("connect failed")

                socket.connect.side_effect = fail_connection
                with (patch.object(app, "WebClient", return_value=client),
                      patch.object(app, "SocketModeClient", return_value=socket)):
                    bridge = app.Application(config)
                    with self.assertRaisesRegex(RuntimeError, "connect failed"):
                        bridge.run()
                self.assertTrue(bridge.processes.closed)
                self.assertTrue(bridge.workers.closed)
                self.assertEqual(signal.getsignal(signal.SIGTERM), previous_signal)
                socket.close.assert_called_once()
        self.assertIsNot(runners[0], runners[1])


if __name__ == "__main__":
    unittest.main()
