import json
from pathlib import Path
import sys
import tempfile
import unittest

from support import Backend, event


class BridgeTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name).resolve()
        self.home = root / "app"
        workspace = root / "workspace"
        workspace.mkdir()
        self.project = root / "project"
        self.project.mkdir()
        self.log = root / "runs.jsonl"
        self.release = root / "release"
        handler = root / "handler.py"
        handler.write_text("""import json, os, sys, time
from pathlib import Path
prompt = sys.stdin.read()
root = Path(__file__).parent
with (root / 'runs.jsonl').open('a') as log:
    log.write(json.dumps({'args': sys.argv[1:], 'cwd': os.getcwd(), 'prompt': prompt}) + '\\n')
if prompt.endswith('hold'):
    while not (root / 'release').exists():
        time.sleep(.01)
if prompt.endswith('AUTHFAIL'):
    print(json.dumps({'error': {'code': 'auth_required', 'provider': 'Claude', 'message': 'fixture-private-secret'}}))
    raise SystemExit(1)
session = sys.argv[1] if len(sys.argv) > 1 else 'synthetic-session'
print(json.dumps({'session_id': session, 'answer': 'synthetic answer'}))
""")
        args = [sys.executable, str(handler)]
        self.backend = Backend(self.home, {
            "workspace": str(workspace),
            "projects": {"demo": str(self.project)},
            "commands": {"hook": {"start": args, "resume": [*args, "{session_id}"]}},
        })
        self.addCleanup(self.backend.stop)

    def submit(self, **fields):
        return self.backend.request("POST", "/slack/run", event(**fields))["job"]

    def runs(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_resume_delivery_claim_and_durable_deduplication(self):
        b = self.backend
        request = event(text="hook inspect demo")
        job = b.request("POST", "/slack/run", request)["job"]
        b.wait(job)
        self.assertTrue(b.request("POST", "/slack/claim", {"job": job})["claimed"])
        self.assertFalse(b.request("POST", "/slack/claim", {"job": job})["claimed"])
        b.request("POST", "/slack/delivered", {"job": job, "ts": "2000000002.000001"})

        followup = self.submit(
            ts="2000000004.000001",
            messages=[
                {"ts": "2000000001.000001", "user": "UTEST", "text": "old request"},
                {"ts": "2000000002.000001", "user": "UTEST", "text": "own generated answer"},
                {"ts": "2000000003.000001", "user": "UOTHER", "text": "extra context"},
            ],
        )
        b.wait(followup)
        first, resumed = self.runs()
        self.assertEqual(first["args"], [])
        self.assertEqual(resumed["args"], ["synthetic-session"])
        self.assertEqual(resumed["cwd"], str(self.project))
        self.assertIn("extra context", resumed["prompt"])
        self.assertNotIn("old request", resumed["prompt"])
        self.assertNotIn("own generated answer", resumed["prompt"])

        b.stop()
        b.start()
        receipt = b.request("POST", "/slack/run", request)
        self.assertEqual((receipt["job"], receipt["status"]), (job, "delivered"))
        self.assertEqual(len(self.runs()), 2)

    def test_sessions_are_isolated_across_channel_user_and_workspace(self):
        b = self.backend
        b.wait(self.submit())
        for scope in ({"channel": "DOTHER"}, {"user": "UOTHER"}, {"team": "EOTHER"}):
            b.wait(self.submit(**scope))
        b.wait(self.submit(ts="2000000005.000001", text="hook inspect demo"))
        runs = self.runs()
        self.assertTrue(all(not run["args"] for run in runs))
        self.assertEqual(runs[-1]["cwd"], str(self.project))

    def test_each_thread_runs_in_order_other_threads_can_finish_first(self):
        b = self.backend
        first = self.submit(text="hook hold")
        b.wait(first, "running")
        second = self.submit(ts="2000000002.000001", text="hook followup")
        b.wait(self.submit(channel="GOTHER"))
        b.wait(first, "running")
        b.wait(second, "queued")
        self.release.touch()
        b.wait(first)
        b.wait(second)
        self.assertEqual(self.runs()[-1]["args"], ["synthetic-session"])

    def test_failed_requests_expose_safe_errors_and_claim_delivery_once_without_a_session(self):
        b = self.backend
        job = self.submit(text="hook AUTHFAIL")
        result = b.wait(job, "failed")
        self.assertEqual(result["error"]["code"], "auth_required")
        self.assertIn("claude auth login", result["error"]["message"])
        self.assertNotIn("answer", result)
        self.assertNotIn("fixture-private-secret", json.dumps(result))
        self.assertTrue(b.request("POST", "/slack/claim", {"job": job})["claimed"])
        self.assertFalse(b.request("POST", "/slack/claim", {"job": job})["claimed"])
        self.assertTrue(b.request("POST", "/slack/delivered", {"job": job, "ts": "2000000002.000001"})["ok"])
        b.wait(job, "delivered")
        b.wait(self.submit(ts="2000000003.000001"))
        self.assertEqual(self.runs()[-1]["args"], [])
        b.stop()
        self.assertNotIn("fixture-private-secret", (self.home / "stderr.log").read_text())

    def test_subprocess_input_is_not_interpolated_by_a_shell(self):
        marker = self.home / "must-not-exist"
        self.backend.wait(self.submit(text=f"hook $(touch {marker}) ; echo nope"))
        self.assertFalse(marker.exists())
        self.assertIn("$(touch", self.runs()[0]["prompt"])


if __name__ == "__main__":
    unittest.main()
