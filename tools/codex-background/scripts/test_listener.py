#!/usr/bin/env python3
"""Focused persistence and delivery tests for the background listener."""

import json
import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import listener


SOURCE = "01a0cf04-784f-7973-9c3e-6b5fae8609c1"
CHILD = "01a0cefe-6b21-7450-946b-aaea8185e27f"
TURN = "01a0cf05-0860-7833-b0f4-ae1c6c50e881"
TOKEN = "5f8f230f820aed69"


class ListenerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.home = root / "background"
        self.sessions = root / "codex" / "sessions" / "2026" / "09" / "23"
        self.sessions.mkdir(parents=True)
        self.child_path = self.sessions / f"rollout-test-{CHILD}.jsonl"
        self.source_path = self.sessions / f"rollout-test-{SOURCE}.jsonl"
        self.patches = [
            patch.dict(os.environ, {"CODEX_HOME": str(root / "codex")}),
            patch.object(listener, "HOME", self.home),
            patch.object(listener, "DATABASE", self.home / "state.sqlite3"),
        ]
        for item in self.patches:
            item.start()
            self.addCleanup(item.stop)
        self.db = listener.connect()
        self.addCleanup(lambda: self.db.close())
        with self.db:
            self.db.execute(
                "INSERT INTO jobs (token, source_id, child_id, label, created_at) VALUES (?, ?, ?, ?, ?)",
                (TOKEN, SOURCE, CHILD, "fixture task", time.time()),
            )

    def append(self, path, kind, payload, ordinal):
        with path.open("ab") as stream:
            stream.write((json.dumps({"type": kind, "payload": payload, "ordinal": ordinal}) + "\n").encode())

    def queue(self, args, **_kwargs):
        message = args[args.index("--message") + 1]
        self.append(self.source_path, "event_msg", {"type": "user_message", "message": message}, 1)
        self.queued.append(message)
        return SimpleNamespace(returncode=0, stdout=f"Queued message 11111111-1111-1111-1111-111111111111 for thread {SOURCE}.\n")

    def test_progress_completion_restart_and_partial_line(self):
        self.queued = []
        self.append(self.child_path, "event_msg", {"type": "task_started", "turn_id": TURN}, 1)
        self.append(self.child_path, "response_item", {
            "type": "message", "role": "assistant", "phase": "commentary",
            "content": [{"type": "output_text", "text": "Milestone reached."}],
            "internal_chat_message_metadata_passthrough": {"turn_id": TURN},
        }, 2)
        with patch.object(listener, "codex_command", return_value="codex"), patch.object(listener.subprocess, "run", self.queue):
            listener.run_once(self.db)
            self.assertEqual(len(self.queued), 1)
            self.assertIn("Milestone reached.", self.queued[0])
            self.db.close()
            self.db = listener.connect()
            listener.run_once(self.db)
            self.assertEqual(len(self.queued), 1)
            with self.child_path.open("ab") as stream:
                stream.write(b'{"type":"event_msg","payload":{"type":"task_complete"')
            listener.run_once(self.db)
            self.assertEqual(len(self.queued), 1)
            with self.child_path.open("ab") as stream:
                stream.write(b',"turn_id":"' + TURN.encode() +
                             b'","last_agent_message":"Finished."},"ordinal":3}\n')
            listener.run_once(self.db)
            self.assertEqual(len(self.queued), 2)
            self.assertIn("Finished.", self.queued[1])
            listener.run_once(self.db)
            self.assertEqual(len(self.queued), 2)
        states = [row[0] for row in self.db.execute("SELECT state FROM deliveries ORDER BY created_at")]
        self.assertEqual(states, ["sent", "sent"])

    def test_pending_worktree_resolves_by_marker(self):
        with self.db:
            self.db.execute("UPDATE jobs SET child_id = NULL WHERE token = ?", (TOKEN,))
        self.append(self.child_path, "response_item", {
            "type": "function_call_output", "name": "create_thread",
            "output": f"prompt included [codex-background-id: {TOKEN}]",
        }, 1)
        self.append(self.child_path, "event_msg", {"type": "task_started", "turn_id": TURN}, 2)
        self.append(self.child_path, "event_msg", {
            "type": "task_complete", "turn_id": TURN, "last_agent_message": "Worktree ready and done."
        }, 3)
        self.queued = []
        with patch.object(listener, "codex_command", return_value="codex"), patch.object(listener.subprocess, "run", self.queue):
            listener.run_once(self.db)
        job = self.db.execute("SELECT child_id, state FROM jobs WHERE token = ?", (TOKEN,)).fetchone()
        self.assertEqual(tuple(job), (CHILD, "complete"))
        self.assertEqual(len(self.queued), 1)

    def test_ambiguous_crash_never_resends(self):
        self.append(self.child_path, "event_msg", {"type": "task_complete", "turn_id": TURN}, 1)
        with patch.object(listener, "codex_command", return_value="codex"), patch.object(
            listener.subprocess, "run", side_effect=subprocess.TimeoutExpired("codex queue", 30)
        ):
            listener.run_once(self.db)
        listener.run_once(self.db)
        state = self.db.execute("SELECT state FROM deliveries").fetchone()[0]
        self.assertEqual(state, "uncertain")
        event_id, message = self.db.execute("SELECT event_id, message FROM deliveries").fetchone()
        self.append(self.source_path, "response_item", {"type": "custom_tool_call", "input": message}, 1)
        listener.run_once(self.db)
        self.assertEqual(self.db.execute("SELECT state FROM deliveries").fetchone()[0], "uncertain")
        self.append(self.source_path, "response_item", {
            "type": "message", "role": "user", "content": [{"type": "input_text", "text": message}]
        }, 2)
        listener.run_once(self.db)
        self.assertEqual(self.db.execute("SELECT state FROM deliveries").fetchone()[0], "sent")
        self.assertIn(event_id, message)


if __name__ == "__main__":
    unittest.main()
