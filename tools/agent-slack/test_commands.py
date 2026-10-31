import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from commands import Command, Executor, load_commands
from process_runner import ProcessRunner


class CommandConfigurationTests(unittest.TestCase):
    def load(self, config):
        with patch.dict(os.environ, {"AGENT_SLACK_COMMANDS": json.dumps(config)}, clear=True):
            return load_commands()

    def test_arbitrary_keywords_and_executables(self):
        entry = {"start": [sys.executable, "-c", "start"],
                 "resume": [sys.executable, "-c", "resume", "{session_id}"]}
        commands = self.load({"!work": entry, "Review": entry})
        self.assertEqual(commands["!work"], commands["Review"])
        self.assertEqual(commands["Review"].resume[-1], "{session_id}")

    def test_relative_executable_is_resolved_before_workspace_changes(self):
        with tempfile.TemporaryDirectory(dir=".") as directory:
            executable = Path(directory) / "custom tool"
            executable.write_text("#!/bin/sh\nexit 0\n")
            executable.chmod(0o700)
            entry = {"start": [str(executable)], "resume": [str(executable), "{session_id}"]}
            commands = self.load({"work": entry})
            self.assertEqual(commands["work"].start[0], str(executable.resolve()))

    def test_command_changes_change_session_identity(self):
        original = Command(("tool",), ("tool", "{session_id}"))
        self.assertNotEqual(original.key, Command(("tool", "new"), original.resume).key)
        self.assertNotEqual(original.key, Command(original.start, ("other", "{session_id}")).key)

    def test_invalid_configurations_are_rejected(self):
        entry = {"start": [sys.executable], "resume": [sys.executable, "{session_id}"]}
        configs = [None, [], {}, {"": entry}, {"two words": entry}, {"bad\0": entry},
                   {"work": "codex"}, {"work": None}, {"work": {}},
                   {"work": {**entry, "extra": []}}]
        for mode in ("start", "resume"):
            for args in (None, "command", [], [1], [""], ["bad\0"], ["/missing/command"]):
                configs.append({"work": {**entry, mode: args}})
        configs += [{"work": {**entry, "resume": [sys.executable]}},
                    {"work": {**entry, "start": [sys.executable, "{session_id}"]}}]
        for config in configs:
            with self.subTest(config=config), self.assertRaises(ValueError):
                self.load(config)
        for raw in ("", "bad json"):
            with patch.dict(os.environ, {"AGENT_SLACK_COMMANDS": raw}), self.assertRaises(ValueError):
                load_commands()


class CommandExecutionTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name)
        self.command = Command(("tool",), ("tool", "--resume", "{session_id}"))

    def response(self, stdout, session=None, returncode=0, stderr=""):
        result = type("Result", (), {"stdout": stdout, "returncode": returncode, "stderr": stderr})()
        with patch("commands.processes.run", return_value=result):
            return Executor(self.command, self.path).run("prompt", session)

    def test_rejects_invalid_output_or_different_resumed_session(self):
        for response in ("", "not JSON", "[]", "null", "{}",
                         '{"session_id":42,"answer":"ok"}',
                         '{"session_id":" ","answer":"ok"}',
                         '{"session_id":"s","answer":" "}',
                         '{"session_id":"s","answer":null}'):
            with self.subTest(response=response), self.assertRaises(RuntimeError):
                self.response(response)
        with self.assertRaisesRegex(RuntimeError, "different session"):
            self.response('{"session_id":"other","answer":"ok"}', session="s")
        with self.assertRaisesRegex(RuntimeError, "exit 7.*failed"):
            self.response("", returncode=7, stderr="failed")

    def test_custom_command_start_and_resume_with_real_processes(self):
        script = self.path / "custom tool.py"
        script.write_text('''import json, os, sys
prompt = sys.stdin.read()
assert not any(key.startswith(("SLACK_", "AGENT_SLACK_")) for key in os.environ)
answer = json.dumps({"prompt": prompt, "args": sys.argv[1:], "cwd": os.getcwd(),
                     "native_setting": os.environ.get("CUSTOM_SETTING")})
print(json.dumps({"session_id": "saved session", "answer": answer}))
''')
        literal = "literal ; $(never-run) {braces}"
        command = Command((sys.executable, str(script), literal),
                          (sys.executable, str(script), literal, "--resume", "{session_id}"))
        runner = ProcessRunner()
        self.addCleanup(runner.close)
        with (patch("commands.processes", runner),
              patch.dict(os.environ, {"SLACK_USER_TOKEN": "secret", "AGENT_SLACK_COMMANDS": "secret",
                                      "CUSTOM_SETTING": "native"})):
            for session in (None, "saved session"):
                with self.subTest(session=session):
                    returned, answer = Executor(command, self.path).run("hello 🌍\nnext", session)
                    self.assertEqual(returned, "saved session")
                    details = json.loads(answer)
                    self.assertEqual(details, {"prompt": "hello 🌍\nnext", "cwd": str(self.path.resolve()),
                                              "native_setting": "native", "args": [literal] +
                                              (["--resume", session] if session else [])})


if __name__ == "__main__":
    unittest.main()
