import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "agents"))
from errors import HookError, classify


class ErrorTests(unittest.TestCase):
    def test_classifier_only_returns_fixed_diagnostics(self):
        private = "fixture-private-secret"
        for text, code in [
            ("OAuth token has expired", "auth_required"),
            ("429 rate limit", "usage_limit"),
            ("approval required", "permission_required"),
            ("session not found", "session_invalid"),
            ("unexpected failure", "command_failed"),
        ]:
            error = classify(text + " " + private, "Claude")
            self.assertEqual(error.code, code)
            self.assertNotIn(private, str(error))

    def test_cli_wrappers_report_expired_login_without_leaking_raw_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for provider in ["claude", "codex"]:
                executable = root / provider
                executable.write_text(
                    "#!"
                    + sys.executable
                    + '\nimport json\nprint(json.dumps({"is_error":True,"result":"OAuth token has expired fixture-private-secret"}))\nraise SystemExit(1)\n'
                )
                executable.chmod(0o700)
                wrapper = (
                    Path(__file__).resolve().parents[1] / "agents" / f"{provider}.py"
                )
                env = {
                    **os.environ,
                    "PATH": str(root) + os.pathsep + os.environ.get("PATH", ""),
                }
                result = subprocess.run(
                    [sys.executable, str(wrapper)],
                    input="health check",
                    capture_output=True,
                    text=True,
                    env=env,
                    cwd=root,
                )
                self.assertEqual(result.returncode, 1)
                error = json.loads(result.stdout)["error"]
                self.assertEqual(error["code"], "auth_required")
                self.assertEqual(error["provider"].lower(), provider)
                self.assertNotIn(
                    "fixture-private-secret", result.stdout + result.stderr
                )


if __name__ == "__main__":
    unittest.main()
