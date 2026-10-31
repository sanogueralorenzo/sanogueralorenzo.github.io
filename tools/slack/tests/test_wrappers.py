import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from commands import Command, Executor
from process_runner import ProcessRunner


# Fake native CLIs: the wrappers still run as real executables, in the selected CWD.
CLI = '''#!{python}
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
prompt = sys.stdin.read()
assert not set(args) & {{"--model", "--config", "--effort", "--permission-mode", "--settings"}}
if "fail" in prompt:
    print("native failure", file=sys.stderr)
    if Path(sys.argv[0]).name == "claude" and "plain" not in prompt:
        print(json.dumps({{"is_error": True, "result": "native failure"}}))
    sys.exit(7)
answer = json.dumps({{"prompt": prompt, "cwd": os.getcwd(), "args": args}})
if Path(sys.argv[0]).name == "codex":
    Path(args[args.index("-o") + 1]).write_text(answer)
    if "resume" in args:
        assert args[-2] == "session-1"
    else:
        assert args[args.index("-C") + 1] == os.getcwd()
    print(json.dumps({{"type": "thread.started", "thread_id": "session-1"}}))
else:
    if "--resume" in args:
        assert args[-1] == "session-1"
    print(json.dumps({{"session_id": "session-1", "result": answer}}))
'''


class WrapperTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name)
        self.bin = self.path / "bin"
        self.bin.mkdir()
        for name in ("codex", "claude"):
            executable = self.bin / name
            executable.write_text(CLI.format(python=sys.executable))
            executable.chmod(0o700)
        self.runner = ProcessRunner()
        self.addCleanup(self.runner.close)
        path = patch.dict(os.environ, {"PATH": str(self.bin) + os.pathsep + os.environ["PATH"]})
        path.start()
        self.addCleanup(path.stop)

    def run_wrapper(self, name, prompt, session_id):
        wrapper = str((Path(__file__).resolve().parent.parent / "wrappers" / f"{name}.py").resolve())
        command = Command((wrapper,), (wrapper, "{session_id}"))
        return Executor(self.runner).run(command, prompt, self.path, session_id)

    def test_wrappers_normalize_start_and_resume_without_overriding_settings(self):
        for name in ("codex", "claude"):
            for session in (None, "session-1"):
                with self.subTest(command=name, session=session):
                    returned, answer = self.run_wrapper(name, "hello 🌍\nnext", session)
                    self.assertEqual(returned, "session-1")
                    details = json.loads(answer)
                    self.assertEqual(details["prompt"], "hello 🌍\nnext")
                    self.assertEqual(details["cwd"], str(self.path.resolve()))
                    self.assertEqual(details["args"][:2], ["exec", "resume"] if name == "codex" and session
                                     else ["exec", "--json"] if name == "codex" else ["-p", "--output-format"])

    def test_native_failures_are_errors_instead_of_slack_answers(self):
        for name in ("codex", "claude"):
            for prompt in ("fail", "plain fail"):
                with self.subTest(command=name, prompt=prompt), self.assertRaisesRegex(RuntimeError, "native failure"):
                    self.run_wrapper(name, prompt, None)


if __name__ == "__main__":
    unittest.main()
