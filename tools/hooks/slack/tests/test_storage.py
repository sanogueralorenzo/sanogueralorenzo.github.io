"""Persisted config and session keys survive the implementation change."""

import hashlib
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

from support import Backend, event


class StorageTests(unittest.TestCase):
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
                    backend.request("POST", "/run", event(text="hook inspect demo"))[
                        "status"
                    ],
                    "delivered",
                )
                self.assertEqual(
                    backend.request("GET", "/jobs/" + uncertain)["status"], "sending"
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
                    "POST", "/run", event(ts="2000000004.000001", messages=context)
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
