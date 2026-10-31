import io
import json
import os
import signal
import sys
import tempfile
import unittest
from collections import deque
from contextlib import redirect_stdout
from pathlib import Path
from threading import Event, Lock
from types import ModuleType, SimpleNamespace
from unittest.mock import Mock, patch

import agent_slack as reply
import conversation
from thread_queue import ThreadQueue


def message(ts, text="work first", **extra):
    return {"type": "message", "user": "U123", "channel": "C123", "ts": ts,
            "text": text, **extra}


class ThreadQueueTests(unittest.TestCase):
    def test_busy_thread_preserves_order_without_occupying_another_worker(self):
        started, release, next_started, other_done = Event(), Event(), Event(), Event()
        calls = []

        def process(event, parsed):
            self.assertEqual(parsed, "parsed")
            calls.append(event["ts"])
            if event["ts"] == "1":
                started.set()
                if not release.wait(5):
                    raise RuntimeError("Test did not release the first request")
            elif event["ts"] == "2":
                next_started.set()
            else:
                other_done.set()

        workers = ThreadQueue(process, max_workers=2)
        try:
            workers.submit(message("1"), "parsed")
            self.assertTrue(started.wait(5))
            workers.submit(message("2", thread_ts="1"), "parsed")
            # The same root timestamp in another channel is a different thread.
            workers.submit(message("3", channel="C456", thread_ts="1"), "parsed")
            self.assertTrue(other_done.wait(5))
            self.assertFalse(next_started.is_set())
        finally:
            release.set()
            workers.close()
        self.assertEqual(calls, ["1", "3", "2"])

    def test_worker_limit_and_shutdown_drain_all_queued_threads(self):
        release, full = Event(), Event()
        lock = Lock()
        active = maximum = completed = 0

        def process(event, parsed):
            nonlocal active, maximum, completed
            with lock:
                active += 1
                maximum = max(maximum, active)
                if active == 2:
                    full.set()
            if not release.wait(5):
                raise RuntimeError("Test did not release the workers")
            with lock:
                active -= 1
                completed += 1

        workers = ThreadQueue(process, max_workers=2)
        try:
            for ts in range(5):
                workers.submit(message(str(ts)), "parsed")
            self.assertTrue(full.wait(5))
            with lock:
                self.assertEqual(active, 2)
        finally:
            release.set()
            workers.close()
        self.assertEqual(maximum, 2)
        self.assertEqual(completed, 5)
        with self.assertRaisesRegex(RuntimeError, "closed"):
            workers.submit(message("6"), "parsed")

    def test_failed_message_does_not_block_followups(self):
        calls = []
        release = Event()

        def process(event, parsed):
            self.assertEqual(parsed, "parsed")
            calls.append(event["ts"])
            if event["ts"] == "1":
                if not release.wait(5):
                    raise RuntimeError("Test did not enqueue the followup")
                raise RuntimeError("CLI failed")

        workers = ThreadQueue(process, max_workers=1)
        with patch("thread_queue.logging.Logger.exception") as log:
            try:
                workers.submit(message("1"), "parsed")
                workers.submit(message("2", thread_ts="1"), "parsed")
            finally:
                release.set()
                workers.close()
        self.assertEqual(calls, ["1", "2"])
        log.assert_called_once()

    def test_bridge_runs_parallel_sessions_with_worker_owned_sqlite_connections(self):
        independent_started = Event()
        delivered = Event()
        calls, posts, sockets, reactions = [], [], [], []
        post_lock = Lock()
        messages = [
            message("1700000001.000001"),
            message("1700000001.000001"),  # Duplicate delivery must not execute twice.
            message("1700000002.000001", "work followup", thread_ts="1700000001.000001"),
            message("1700000003.000001", "work independent"),
        ]

        def run(prompt, session_id):
            name = prompt.split()[-1]
            calls.append((name, session_id))
            if name == "first":
                if not independent_started.wait(5):
                    raise RuntimeError("Another Slack thread was blocked")
            elif name == "independent":
                # Even a follow-up waiting behind a busy thread is acknowledged immediately.
                self.assertIn(("add", "1700000002.000001", "eyes"), reactions)
                self.assertNotIn(("followup", "session-first"), calls)
                independent_started.set()
            return session_id or f"session-{name}", f"answer {name}"

        class Client:
            def __init__(self, token):
                self.token = token

            def auth_test(self):
                self.assert_user_token()
                return {"team_id": "T123", "user_id": "U123"}

            def conversations_replies(self, **kwargs):
                return {"messages": [event for event in messages if event["ts"] <= kwargs["latest"]]}

            def reactions_add(self, **kwargs):
                self.assert_user_token()
                with post_lock:
                    reactions.append(("add", kwargs["timestamp"], kwargs["name"]))

            def reactions_remove(self, **kwargs):
                self.assert_user_token()
                with post_lock:
                    reactions.append(("remove", kwargs["timestamp"], kwargs["name"]))

            def assert_user_token(self):
                if not self.token.startswith("xoxp-"):
                    raise RuntimeError("Reactions must use the authorized user token")

            def chat_postMessage(self, **kwargs):
                with post_lock:
                    posts.append(kwargs)
                    if len(posts) == 3:
                        delivered.set()
                    return {"ts": f"1700000004.{len(posts):06d}"}

        class Inbox:
            def __init__(self):
                self.events = deque()

            def put(self, event):
                self.events.append(event)

            def get(self):
                if self.events:
                    return self.events.popleft()
                if not delivered.wait(5):
                    raise RuntimeError("The bridge did not finish the test requests")
                signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)

        class Socket:
            def __init__(self, **kwargs):
                if kwargs["app_token"] != "xapp-test" or kwargs["web_client"].token != "xoxp-test":
                    raise RuntimeError("Socket Mode must use the app token and authorized user client")
                self.socket_mode_request_listeners = []
                self.closed = False
                sockets.append(self)

            def send_socket_mode_response(self, response):
                pass

            def connect(self):
                for index, event in enumerate(messages):
                    request = SimpleNamespace(type="events_api", envelope_id=str(index),
                                              payload={"team_id": "T123", "event": event})
                    for listener in self.socket_mode_request_listeners:
                        listener(self, request)
                foreign = SimpleNamespace(type="events_api", envelope_id="foreign",
                                          payload={"team_id": "TOTHER", "event": message("1700000005.000001")})
                for listener in self.socket_mode_request_listeners:
                    listener(self, foreign)

            def close(self):
                self.closed = True

        sdk = ModuleType("slack_sdk")
        sdk.WebClient = Client
        socket_mode = ModuleType("slack_sdk.socket_mode")
        socket_mode.SocketModeClient = Socket
        response = ModuleType("slack_sdk.socket_mode.response")
        response.SocketModeResponse = SimpleNamespace
        modules = {"slack_sdk": sdk, "slack_sdk.socket_mode": socket_mode,
                   "slack_sdk.socket_mode.response": response}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            env = {"SLACK_APP_TOKEN": "xapp-test",
                   "SLACK_USER_TOKEN": "xoxp-test", "SLACK_USER_ID": "U123",
                   "AGENT_SLACK_COMMANDS": json.dumps({"work": "codex"}), "AGENT_SLACK_PROJECTS": "{}", "AGENT_SLACK_WORKSPACE": directory,
                   "AGENT_SLACK_STATE_DIR": str(path / "state")}
            with (patch.dict(os.environ, env, clear=True), patch.dict(sys.modules, modules),
                  patch.object(reply, "require_available"),
                  patch.object(reply, "processes", Mock(closed=False)) as processes,
                  patch.object(conversation, "provider_for", return_value=Mock(run=run)),
                  patch.object(reply.queue, "Queue", Inbox),
                  patch("thread_queue.logging.Logger.exception") as errors,
                  redirect_stdout(io.StringIO())):
                previous_signal = signal.getsignal(signal.SIGTERM)
                with self.assertRaises(KeyboardInterrupt):
                    reply.main([])
                errors.assert_not_called()
                processes.close.assert_called_once()
                self.assertEqual(signal.getsignal(signal.SIGTERM), previous_signal)
            state = reply.State(path / "state")
            try:
                self.assertEqual(state.session("T123", "C123", messages[0]["ts"])[:2],
                                 ("codex", "session-first"))
                self.assertEqual(state.session("T123", "C123", messages[-1]["ts"])[:2],
                                 ("codex", "session-independent"))
            finally:
                state.db.close()
        self.assertCountEqual(calls, [("first", None), ("independent", None), ("followup", "session-first")])
        self.assertEqual(len(posts), 3)
        self.assertEqual(sum(name == "robot_face" for _, _, name in reactions), 3)
        self.assertEqual(sum(name == "white_check_mark" for _, _, name in reactions), 3)
        self.assertEqual(sum(action == "remove" and name == "eyes" for action, _, name in reactions), 3)
        self.assertTrue(sockets[0].closed)


if __name__ == "__main__":
    unittest.main()
