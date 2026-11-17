"""Thread stop commands cancel work without losing native conversation state."""

import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

from support import Backend, configuration, dead, event, wait_until


class StopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name).resolve()
        self.addCleanup(self.temp.cleanup)

    def start(self, config):
        backend = Backend(self.home, config)
        self.addCleanup(backend.stop)
        return backend

    def submit(self, backend, **extra):
        return backend.request("POST", "/slack/run", event(**extra))["job"]

    def test_stop_kills_running_descendants_clears_queue_and_preserves_session_and_project(self):
        project = self.home / "project"
        project.mkdir()
        script = self.home / "agent.py"
        script.write_text('''import json,os,subprocess,sys,time
from pathlib import Path
root=Path(__file__).parent
prompt=sys.stdin.read()
session=sys.argv[1] if len(sys.argv)>1 else 'early-session'
print(json.dumps({'type':'session','session_id':session}),flush=True)
with (root/'runs.jsonl').open('a') as log:
 log.write(json.dumps({'session':session,'cwd':os.getcwd(),'prompt':prompt,'resumed':len(sys.argv)>1})+'\\n')
if prompt.endswith('hold'):
 child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)'])
 (root/'pids.json').write_text(json.dumps([os.getpid(),child.pid]))
 time.sleep(30)
print(json.dumps({'session_id':session,'answer':'completed','chat_url':'codex://threads/00000000-0000-4000-8000-000000000001'}))
''')
        config = configuration(self.home)
        args = [sys.executable, str(script)]
        config["commands"] = {
            key: {"start": args, "resume": args + ["{session_id}"]}
            for key in ("chat", "claude")
        }
        config["projects"] = {"demo": str(project)}
        b = self.start(config)
        running = self.submit(b, text="chat demo hold")
        wait_until((self.home / "pids.json").exists)
        with sqlite3.connect(self.home / "hooks/slack/sessions.sqlite3") as db:
            wait_until(lambda: db.execute("SELECT count(*) FROM sessions").fetchone()[0] == 1)
            saved = db.execute("SELECT * FROM sessions").fetchone()
            queued = self.submit(b, ts="2000000002.000001", text="claude must not run")
            self.assertEqual(b.wait(queued, "queued")["status"], "queued")
            other = self.submit(b, channel="DOTHER", text="chat independent")
            b.wait(other)
            events = b.socket()
            self.addCleanup(events.close)
            stop_event = event(ts="2000000003.000001", text="ClAuDe\tSTOP ")
            stopped = b.request("POST", "/slack/run", stop_event)["job"]
            self.assertEqual({events.receive()["job"], events.receive()["job"]}, {running, queued})
            self.assertEqual(b.wait(stopped)["answer"], "Stopping work in this thread.")
            for job in (running, queued):
                result = b.wait(job, "cancelled")
                self.assertNotIn("answer", result)
                self.assertFalse(b.request("POST", "/slack/claim", {"job": job})["claimed"])
                self.assertEqual(db.execute("SELECT answer,request FROM jobs WHERE id=?", (job,)).fetchone(), (None, None))
            pids = json.loads((self.home / "pids.json").read_text())
            wait_until(lambda: all(dead(pid) for pid in pids))
            self.assertEqual(db.execute("SELECT * FROM sessions WHERE thread=?", (saved[0],)).fetchone(), saved)
            self.assertEqual(b.wait(other)["answer"].splitlines()[0], "completed")
            self.assertIsNone(b.request("GET", "/health")["hooks"]["slack"]["error"])
            followup = self.submit(b, ts="2000000004.000001", text="chat continue", messages=[{"ts":"2000000002.000001","user":"UOTHER","text":"unfinished context"}])
            self.assertIn("[chat]", b.wait(followup)["answer"])
            runs = [json.loads(line) for line in (self.home / "runs.jsonl").read_text().splitlines()]
            self.assertEqual(len(runs), 3)
            self.assertEqual(runs[-1]["session"], "early-session")
            self.assertTrue(runs[-1]["resumed"])
            self.assertEqual(runs[-1]["cwd"], str(project))
            self.assertIn("unfinished context", runs[-1]["prompt"])
            # Redelivering the same stop event cannot cancel newer work.
            self.assertEqual(b.request("POST", "/slack/run", stop_event)["job"], stopped)
            b.wait(followup)
            b.stop()
            b.start()
            for job in (running, queued):
                b.wait(job, "cancelled")
            recovered = b.request("POST", "/slack/recover", {"team":"ETEST","user":"UTEST"})["jobs"]
            self.assertEqual({item["job"] for item in recovered}, {stopped, other, followup})

    def test_stop_withholds_unsent_answers_but_preserves_claimed_sends_and_other_scopes(self):
        config = configuration(self.home)
        b = self.start(config)
        unsent = self.submit(b)
        b.wait(unsent)
        sending = self.submit(b, ts="2000000002.000001")
        b.wait(sending)
        self.assertTrue(b.request("POST", "/slack/claim", {"job": sending})["claimed"])
        others = [self.submit(b, **extra) for extra in (
            {"channel":"DOTHER"}, {"user":"UOTHER"}, {"team":"EOTHER"},
            {"ts":"2000000002.000002","thread_ts":"2000000002.000002"},
        )]
        for job in others:
            b.wait(job)
        stopped = self.submit(b, ts="2000000003.000001", text="hook stop")
        b.wait(stopped)
        b.wait(unsent, "cancelled")
        b.wait(sending, "sending")
        for job in others:
            b.wait(job)
        b.stop()
        b.start()
        b.wait(stopped)
        self.assertTrue(b.request("POST", "/slack/claim", {"job": stopped})["claimed"])
        self.assertFalse(b.request("POST", "/slack/claim", {"job": stopped})["claimed"])
        self.assertTrue(b.request("POST", "/slack/delivered", {"job":stopped,"ts":"2000000004.000001"})["ok"])
        idle = self.submit(b, ts="2000000005.000001", text="hook stop")
        self.assertEqual(b.wait(idle)["answer"], "No pending work in this thread.")
        ordinary = self.submit(b, ts="2000000006.000001", text="hook stop using polling")
        self.assertEqual(b.wait(ordinary)["answer"], "synthetic answer")

    def test_stop_bypasses_a_full_queue_and_frees_capacity(self):
        b = self.start(configuration(self.home, "import time;time.sleep(30)"))
        jobs = [self.submit(b, ts=f"2000000001.{i:06d}") for i in range(100)]
        with self.assertRaises(ValueError):
            self.submit(b, ts="2000000002.000001")
        stopped = self.submit(b, ts="2000000003.000001", text="hook stop")
        b.wait(stopped)
        for job in jobs:
            b.wait(job, "cancelled")
        following = self.submit(b, ts="2000000004.000001")
        b.wait(following, "running")
