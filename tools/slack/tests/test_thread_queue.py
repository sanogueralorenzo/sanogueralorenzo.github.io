import unittest
from threading import Event, Lock
from unittest.mock import patch

from agent_slack.thread_queue import ThreadQueue


def message(ts, text="work first", **extra):
    return {"type": "message", "user": "U123", "channel": "C123", "ts": ts,
            "text": text, **extra}


class ThreadQueueTests(unittest.TestCase):
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
