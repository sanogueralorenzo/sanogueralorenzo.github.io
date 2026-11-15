import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from local.errors import HookError, classify
from local.process import execute


class ErrorTests(unittest.TestCase):
    def test_classifier_only_returns_fixed_diagnostics(self):
        private = 'fixture-private-secret'
        for text, code in [('OAuth token has expired', 'auth_required'), ('429 rate limit', 'usage_limit'),
                           ('approval required', 'permission_required'), ('session not found', 'session_invalid'), ('unexpected failure', 'command_failed')]:
            error = classify(text + ' ' + private, 'Claude').public()
            self.assertEqual(error['code'], code)
            self.assertNotIn(private, json.dumps(error))
        self.assertIn('claude auth login', classify('token expired', 'Claude').public()['message'])
        self.assertIn('codex login', classify('401', 'Codex').public()['message'])

    def test_cli_wrappers_report_expired_login_without_leaking_raw_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for provider in ['claude', 'codex']:
                executable = root / provider
                executable.write_text('#!' + sys.executable + '\nimport json\nprint(json.dumps({"is_error":True,"result":"OAuth token has expired fixture-private-secret"}))\nraise SystemExit(1)\n')
                executable.chmod(0o700)
                wrapper = Path(__file__).resolve().parents[1] / 'agents' / f'{provider}.py'
                env = {**os.environ, 'PATH': str(root) + os.pathsep + os.environ.get('PATH', '')}
                result = subprocess.run([sys.executable, str(wrapper)], input='health check', capture_output=True, text=True, env=env, cwd=root)
                self.assertEqual(result.returncode, 1)
                error = json.loads(result.stdout)['error']
                self.assertEqual(error['code'], 'auth_required')
                self.assertEqual(error['provider'].lower(), provider)
                self.assertNotIn('fixture-private-secret', result.stdout + result.stderr)

    def test_command_error_envelope_cannot_inject_arbitrary_error_text(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'command.py'
            path.write_text('import json\nprint(json.dumps({"error":{"code":"auth_required","provider":"Claude","message":"fixture-private-secret"}}))\nraise SystemExit(1)\n')
            command = {'start': [sys.executable, str(path)], 'resume': [sys.executable, str(path), '{session_id}']}
            with self.assertRaises(HookError) as result:
                execute(command, 'test', Path(folder), None, 2, threading.Event())
            self.assertIn('claude auth login', str(result.exception))
            self.assertNotIn('fixture-private-secret', str(result.exception))

    def test_timeout_explains_the_fix_and_cleans_up(self):
        command = {'start': [sys.executable, '-c', 'import time;time.sleep(30)'], 'resume': []}
        with self.assertRaises(HookError) as result:
            execute(command, 'test', Path.cwd(), None, 0.1, threading.Event())
        self.assertEqual(result.exception.code, 'timeout')
        self.assertIn('timeout_seconds', str(result.exception))


if __name__ == '__main__':
    unittest.main()
