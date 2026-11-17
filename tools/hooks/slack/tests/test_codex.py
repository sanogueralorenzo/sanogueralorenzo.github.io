import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ADAPTER = Path(__file__).resolve().parents[1] / "agents/codex.py"
SESSION = "00000000-0000-4000-8000-000000000001"
FAKE = r'''
import json, os, sys
from pathlib import Path
root = Path(__file__).parent
session = "00000000-0000-4000-8000-000000000001"
mode = (root / "mode").read_text()
def send(value):
    print(json.dumps(value), flush=True)
for line in sys.stdin:
    message = json.loads(line)
    with (root / "requests.jsonl").open("a") as log:
        log.write(json.dumps(message) + "\n")
    method = message["method"]
    if "id" not in message:
        continue
    if method == "initialize":
        result = {}
    elif method in ("thread/start", "thread/resume"):
        if mode == "busy":
            send({"id": message["id"], "error": {"code": -32600, "message": "thread already has an active writer fixture-private-secret"}})
            continue
        result = {"thread": {"id": session}}
    elif method == "turn/start":
        result = {"turn": {"id": "test-turn"}}
        send({"id": message["id"], "result": result})
        if mode == "approval":
            send({"id": "approval-request", "method": "item/commandExecution/requestApproval", "params": {"threadId": session}})
            continue
        for phase, text in [("commentary", "Do not post progress"), ("final_answer", "fixture answer")]:
            send({"method": "item/completed", "params": {"threadId": session, "turnId": "test-turn", "item": {"type": "agentMessage", "phase": phase, "text": text}}})
        send({"method": "turn/completed", "params": {"threadId": session, "turn": {"id": "test-turn", "status": "completed"}}})
        continue
    send({"id": message["id"], "result": result})
(root / "closed").write_text(str(os.getpid()))
'''


class CodexTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.workspace = self.root / "project with spaces"
        self.workspace.mkdir()
        cli = self.root / "codex"
        cli.write_text("#!" + sys.executable + "\n" + FAKE)
        cli.chmod(0o700)
        self.env = {**os.environ, "PATH": str(self.root) + os.pathsep + os.environ["PATH"]}

    def tearDown(self):
        self.temp.cleanup()

    def run_adapter(self, mode="success", session=None):
        (self.root / "mode").write_text(mode)
        result = subprocess.run(
            [sys.executable, str(ADAPTER), *([session] if session else [])],
            input="fixture request", text=True, capture_output=True,
            cwd=self.workspace, env=self.env, timeout=10,
        )
        self.assertTrue((self.root / "closed").exists(), "Return only after runner exit")
        with self.assertRaises(ProcessLookupError):
            os.kill(int((self.root / "closed").read_text()), 0)
        self.assertNotIn("fixture-private-secret", result.stdout + result.stderr)
        return result, json.loads(result.stdout)

    def test_start_and_resume_keep_cwd_identity_and_only_the_final_answer(self):
        for session in (None, SESSION):
            with self.subTest(session=session):
                (self.root / "requests.jsonl").unlink(missing_ok=True)
                result, reply = self.run_adapter(session=session)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(reply, {"session_id": SESSION, "answer": "fixture answer", "chat_url": f"codex://threads/{SESSION}"})
                requests = [json.loads(line) for line in (self.root / "requests.jsonl").read_text().splitlines()]
                self.assertEqual(requests[0]["params"]["clientInfo"]["name"], "browser_hooks")
                start = requests[2]
                self.assertEqual(start["method"], "thread/resume" if session else "thread/start")
                expected = {"cwd": str(self.workspace)}
                if session:
                    expected.update(threadId=SESSION, excludeTurns=True)
                self.assertEqual(start["params"], expected)
                self.assertEqual(requests[3]["params"]["cwd"], str(self.workspace))
                self.assertEqual(requests[3]["params"]["threadId"], SESSION)

    def test_busy_session_reports_actionable_error_without_starting_another_turn(self):
        result, reply = self.run_adapter(mode="busy", session=SESSION)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(reply["error"], {"code": "session_busy", "provider": "Codex"})
        self.assertNotIn("turn/start", (self.root / "requests.jsonl").read_text())

    def test_approval_request_stops_runner_without_auto_approving(self):
        result, reply = self.run_adapter(mode="approval")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(reply["error"]["code"], "permission_required")
        requests = [json.loads(line) for line in (self.root / "requests.jsonl").read_text().splitlines()]
        self.assertTrue(all("approval-request" != item.get("id") for item in requests))


if __name__ == "__main__":
    unittest.main()
