import unittest
from threading import Event, Lock
from unittest.mock import patch

from agent_slack.thread_queue import ThreadQueue


def message(ts, text="work first", **extra):
    return {"type": "message", "user": "U123", "channel": "C123", "ts": ts,
            "text": text, **extra}


class ThreadQueueTests(unittest.TestCase):
    def test_busy_thread_preserves_order_without_occupying_another_worker(self):
        started, release, next_started, other_done = Event(), Event(), Event(), Event()
        calls = []

        def process(event, parsed):
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
            calls.append(event["ts"])
            if event["ts"] == "1":
                if not release.wait(5):
                    raise RuntimeError("Test did not enqueue the followup")
                raise RuntimeError("CLI failed")

        workers = ThreadQueue(process, max_workers=1)
        with patch("agent_slack.thread_queue.logging.Logger.exception") as log:
            try:
                workers.submit(message("1"), "parsed")
                workers.submit(message("2", thread_ts="1"), "parsed")
            finally:
                release.set()
                workers.close()
        self.assertEqual(calls, ["1", "2"])
        log.assert_called_once()


if __name__ == "__main__":
    unittest.main()
