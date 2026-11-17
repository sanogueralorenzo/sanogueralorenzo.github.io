"""Persisted config and session keys survive the implementation change."""

import hashlib
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

from support import Backend, configuration, event


class StorageTests(unittest.TestCase):
    def test_chat_footer_rejects_unsafe_urls(self):
        for url in ('javascript://example', 'https://example.test/) [injected](https://other.test'):
            with self.subTest(url=url), tempfile.TemporaryDirectory() as directory:
                home = Path(directory).resolve()
                output = {"session_id": "synthetic-session", "answer": "answer", "chat_url": url}
                config = configuration(home, script=f'import sys;sys.stdin.read();print({json.dumps(output)!r})')
                backend = Backend(home, config)
                try:
                    job = backend.request("POST", "/slack/run", event())["job"]
                    self.assertEqual(backend.wait(job, "failed")["error"]["code"], "invalid_response")
                finally:
                    backend.stop()

    def test_chat_footer_is_only_on_first_reply_even_with_queued_requests_and_project_change(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory).resolve()
            project = home / "project with spaces"
            project.mkdir()
            config = configuration(home, script='import json,sys;sys.stdin.read();print(json.dumps({"session_id":"synthetic-session","answer":"x"*12000,"chat_url":"codex://threads/00000000-0000-4000-8000-000000000001"}))')
            config["projects"] = {"demo": str(project)}
            backend = Backend(home, config)
            try:
                first = backend.request("POST", "/slack/run", event())["job"]
                second = backend.request("POST", "/slack/run", event(ts="2000000002.000001"))["job"]
                reply = backend.wait(first)["answer"]
                self.assertEqual(len(reply), 12000)
                self.assertTrue(reply.endswith("\n\n[chat](codex://threads/00000000-0000-4000-8000-000000000001)"))
                self.assertEqual(backend.wait(second)["answer"], "x"*12000)
                changed = backend.request("POST", "/slack/run", event(ts="2000000003.000001", text="hook demo"))["job"]
                self.assertEqual(backend.wait(changed)["answer"], "x"*12000)
            finally:
                backend.stop()

    def test_existing_json_keys_and_sessions_resume_without_rewriting_history(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory).resolve()
            folder = home / "hooks/slack"
            folder.mkdir(parents=True)
            project = home / "project-🧪"
            project.mkdir()
            script, log = home / "handler-🧪.py", home / "runs.jsonl"
            script.write_text(
                'import json,os,sys\nprompt=sys.stdin.read()\nwith open(sys.argv[1],"a") as out:out.write(json.dumps({"args":sys.argv[2:],"cwd":os.getcwd(),"prompt":prompt})+"\\n")\nprint(json.dumps({"session_id":sys.argv[2],"answer":"answer"}))\n'
            )
            args = [str(Path(sys.executable).resolve()), str(script), str(log)]
            command = {"start": args, "resume": args + ["{session_id}"]}
            config = {
                "workspace": str(home),
                "projects": {"demo": str(project)},
                "commands": {"hook": command},
            }
            thread = json.dumps(["ETEST", "UTEST", "CTEST", "2000000001.000001"])
            old_job = hashlib.sha256(
                json.dumps(["ETEST", "UTEST", "CTEST", "2000000001.000001"]).encode()
            ).hexdigest()
            uncertain = "a" * 64
            with sqlite3.connect(folder / "sessions.sqlite3") as db:
                db.executescript(
                    "CREATE TABLE jobs(id TEXT PRIMARY KEY,thread TEXT,status TEXT,answer TEXT);CREATE TABLE sessions(thread TEXT PRIMARY KEY,command TEXT,workspace TEXT,session TEXT,context_ts TEXT);CREATE TABLE replies(thread TEXT,ts TEXT,session TEXT,PRIMARY KEY(thread,ts));"
                )
                db.execute(
                    "INSERT INTO jobs VALUES (?,?,?,NULL)",
                    (old_job, thread, "delivered"),
                )
                db.execute(
                    "INSERT INTO jobs VALUES (?,?,?,NULL)",
                    (uncertain, thread, "sending"),
                )
                db.execute(
                    "INSERT INTO sessions VALUES (?,?,?,?,?)",
                    (
                        thread,
                        json.dumps(command, sort_keys=True),
                        str(project),
                        "synthetic-session",
                        "2000000001.000001",
                    ),
                )
                db.execute(
                    "INSERT INTO replies VALUES (?,?,?)",
                    (thread, "2000000002.000001", "synthetic-session"),
                )
            backend = Backend(home, config)
            try:
                self.assertEqual(
                    backend.request("POST", "/slack/run", event(text="hook inspect demo"))[
                        "status"
                    ],
                    "delivered",
                )
                self.assertEqual(
                    backend.request("GET", "/slack/jobs/" + uncertain)["status"], "sending"
                )
                context = [
                    {"ts": "2000000001.000001", "user": "UTEST", "text": "old request"},
                    {
                        "ts": "2000000002.000001",
                        "user": "UTEST",
                        "text": "generated reply",
                    },
                    {
                        "ts": "2000000003.000001",
                        "user": "UOTHER",
                        "text": "fresh context",
                    },
                ]
                job = backend.request(
                    "POST", "/slack/run", event(ts="2000000004.000001", messages=context)
                )["job"]
                backend.wait(job)
                recorded = json.loads(log.read_text())
                self.assertEqual(recorded["args"], ["synthetic-session"])
                self.assertEqual(recorded["cwd"], str(project))
                self.assertIn("fresh context", recorded["prompt"])
                self.assertNotIn("old request", recorded["prompt"])
                self.assertNotIn("generated reply", recorded["prompt"])
            finally:
                backend.stop()
