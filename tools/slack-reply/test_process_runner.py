import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from threading import Thread
from unittest.mock import Mock, patch

from process_runner import ProcessRunner


FAMILY = """
import json, os, signal, subprocess, sys, time
from pathlib import Path
signal.signal(signal.SIGTERM, signal.SIG_IGN)
child = subprocess.Popen([sys.executable, '-c',
    "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); print('ready',flush=True); time.sleep(60)"],
    stdout=subprocess.PIPE, text=True)
child.stdout.readline()
Path(sys.argv[1]).write_text(json.dumps([os.getpid(), child.pid]))
print('ready', flush=True)
if sys.argv[2] == 'wait':
    time.sleep(60)
"""


@unittest.skipUnless(hasattr(os, "killpg"), "Process group cleanup requires POSIX")
class ProcessRunnerTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name)
        self.runner = ProcessRunner()
        self.addCleanup(self.runner.close)

    def assert_stopped(self, pid):
        result = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)],
                                text=True, capture_output=True, check=False)
        status = result.stdout.strip()
        self.assertTrue(not status or status.startswith("Z"), f"Process {pid} is still running: {status}")

    def test_preserves_input_output_and_exit_code_without_pipe_deadlocks(self):
        prompt = "hello 🌍\n" * 20000
        command = [sys.executable, "-c",
                   "import sys; text=sys.stdin.read(); sys.stdout.write(text); sys.stderr.write('e'*200000); sys.exit(7)"]
        result = self.runner.run(command, prompt, self.path, {})
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stdout, prompt)
        self.assertEqual(result.stderr, "e" * 200000)

    def test_cleans_up_children_holding_pipes_after_the_cli_exits(self):
        pids = self.path / "pids.json"
        result = self.runner.run([sys.executable, "-c", FAMILY, str(pids), "exit"],
                                 "", self.path, {})
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "ready\n")
        for pid in json.loads(pids.read_text()):
            self.assert_stopped(pid)

    def test_shutdown_kills_concurrent_process_groups_and_refuses_new_runs(self):
        results, errors = [], []

        def run(path):
            try:
                results.append(self.runner.run([sys.executable, "-c", FAMILY, str(path), "wait"],
                                               "", self.path, {}))
            except Exception as error:
                errors.append(error)

        paths = [self.path / f"pids-{index}.json" for index in range(2)]
        threads = [Thread(target=run, args=(path,)) for path in paths]
        try:
            for thread in threads:
                thread.start()
            deadline = time.monotonic() + 5
            while not all(path.exists() for path in paths) and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(all(path.exists() for path in paths), "CLI fixtures did not start")
        finally:
            self.runner.close()
            for thread in threads:
                thread.join(5)
        self.assertFalse(errors)
        self.assertTrue(all(not thread.is_alive() for thread in threads))
        self.assertEqual([result.returncode for result in results], [-signal.SIGKILL] * 2)
        for path in paths:
            for pid in json.loads(path.read_text()):
                self.assert_stopped(pid)
        with patch("process_runner.subprocess.Popen") as spawn:
            with self.assertRaisesRegex(RuntimeError, "shutting down"):
                self.runner.run([sys.executable, "-c", "pass"], "", self.path, {})
            spawn.assert_not_called()

    def test_execution_error_still_reaps_the_process(self):
        spawn = subprocess.Popen
        children = []

        def fail_communication(*args, **kwargs):
            process = spawn(*args, **kwargs)
            process.communicate = Mock(side_effect=ValueError("decode failed"))
            children.append(process)
            return process

        with patch("process_runner.subprocess.Popen", side_effect=fail_communication):
            with self.assertRaisesRegex(ValueError, "decode failed"):
                self.runner.run([sys.executable, "-c", "import time; time.sleep(60)"],
                                "", self.path, {})
        self.assertIsNotNone(children[0].returncode)
        self.assert_stopped(children[0].pid)


if __name__ == "__main__":
    unittest.main()
