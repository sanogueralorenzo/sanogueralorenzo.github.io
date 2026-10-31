"""Run Slack threads concurrently while keeping each thread's messages in order."""

import logging
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from threading import Lock


class ThreadQueue:
    def __init__(self, process, max_workers=4):
        self.process = process
        self.pool = ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="slack-reply")
        self.queues = {}
        self.lock = Lock()
        self.closed = False

    def submit(self, event):
        key = (event["channel"], event.get("thread_ts") or event["ts"])
        with self.lock:
            if self.closed:
                raise RuntimeError("Slack Reply queue is closed")
            if key in self.queues:
                self.queues[key].append(event)
            else:
                self.queues[key] = deque([event])
                self.pool.submit(self.run, key)

    def run(self, key):
        while True:
            with self.lock:
                event = self.queues[key][0]
            try:
                self.process(event)
            except Exception:
                logging.getLogger(__name__).exception(
                    "Slack Reply could not process %s/%s", event["channel"], event["ts"]
                )
            with self.lock:
                pending = self.queues[key]
                pending.popleft()
                if not pending:
                    del self.queues[key]
                    return

    def close(self):
        with self.lock:
            self.closed = True
        self.pool.shutdown(wait=True)
