import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import providers


def completed(stdout, returncode=0, stderr=""):
    return type("Result", (), {
        "stdout": stdout, "returncode": returncode, "stderr": stderr,
    })()


def pi_events(session_id, answer, stop_reason="stop", settled=True):
    events = [
        {"type": "session", "id": session_id},
        {"type": "message_end", "message": {"role": "assistant",
                                            "content": [{"type": "text", "text": answer}],
                                            "stopReason": stop_reason}},
    ]
    if settled:
        events.append({"type": "agent_settled"})
    return "\n".join(json.dumps(event) for event in events) + "\n"


class ProviderTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        provider_env = patch.dict(os.environ, {}, clear=True)
        provider_env.start()
        self.addCleanup(provider_env.stop)

    def test_missing_cli_is_rejected(self):
        with patch.object(providers.shutil, "which", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "claude CLI is not installed"):
                providers.require_available("claude")

    def test_subprocess_does_not_inherit_slack_tokens(self):
        with patch.dict(os.environ, {"PATH": "/usr/bin", "SLACK_USER_TOKEN": "secret",
                                     "SLACK_APP_TOKEN": "secret", "CLAUDE_CODE_EFFORT_LEVEL": "high",
                                     "CODEX_HOME": "/custom/codex", "CLAUDE_CONFIG_DIR": "/custom/claude"},
                        clear=True):
            with patch.object(providers.processes, "run", return_value=completed("")) as run:
                providers.execute(["claude", "-p"], "prompt", self.path)
        self.assertNotIn("SLACK_USER_TOKEN", run.call_args.kwargs["env"])
        self.assertNotIn("SLACK_APP_TOKEN", run.call_args.kwargs["env"])
        self.assertEqual(run.call_args.kwargs["env"]["CLAUDE_CODE_EFFORT_LEVEL"], "high")
        self.assertEqual(run.call_args.kwargs["env"]["CODEX_HOME"], "/custom/codex")
        self.assertEqual(run.call_args.kwargs["env"]["CLAUDE_CONFIG_DIR"], "/custom/claude")
        self.assertEqual(run.call_args.args[1], "prompt")

    def test_codex_new_session_reads_final_answer_and_session_id(self):
        def fake_execute(command, prompt, workspace, **kwargs):
            Path(command[command.index("-o") + 1]).write_text("final answer")
            self.assertEqual(command, ["codex", "exec", "--json", "-o",
                                      command[command.index("-o") + 1],
                                      "--skip-git-repo-check", "-C", str(self.path), "-"])
            return completed('{"type":"thread.started","thread_id":"new-session"}\n')

        with patch.object(providers, "execute", side_effect=fake_execute):
            session, answer = providers.CodexProvider(self.path, self.path).run("prompt", None)
        self.assertEqual((session, answer), ("new-session", "final answer"))

    def test_codex_resumes_exact_session(self):
        def fake_execute(command, prompt, workspace, **kwargs):
            Path(command[command.index("-o") + 1]).write_text("answer")
            self.assertEqual(command, ["codex", "exec", "resume", "--json", "-o",
                                      command[command.index("-o") + 1],
                                      "--skip-git-repo-check", "session-1", "-"])
            return completed('{"type":"thread.started","thread_id":"session-1"}\n')

        with patch.object(providers, "execute", side_effect=fake_execute):
            session, answer = providers.CodexProvider(self.path, self.path).run(
                "prompt", "session-1",
            )
        self.assertEqual((session, answer), ("session-1", "answer"))

    def test_codex_rejects_different_resumed_session(self):
        def fake_execute(command, prompt, workspace, **kwargs):
            Path(command[command.index("-o") + 1]).write_text("answer")
            return completed('{"type":"thread.started","thread_id":"other"}\n')

        with patch.object(providers, "execute", side_effect=fake_execute):
            with self.assertRaisesRegex(RuntimeError, "different session"):
                providers.CodexProvider(self.path, self.path).run("prompt", "session-1")

    def test_claude_auth_failure_is_reported_instead_of_posted(self):
        payload = json.dumps({"type": "result", "is_error": True, "session_id": "new",
                              "result": "OAuth access token has expired"})
        with patch.object(providers, "execute", return_value=completed(payload, 1)):
            with self.assertRaisesRegex(RuntimeError, "OAuth access token has expired"):
                providers.ClaudeProvider(self.path).run("prompt", None)

    def test_claude_rejects_different_resumed_session(self):
        payload = json.dumps({"type": "result", "is_error": False,
                              "session_id": "other", "result": "answer"})
        with patch.object(providers, "execute", return_value=completed(payload)):
            with self.assertRaisesRegex(RuntimeError, "different session"):
                providers.ClaudeProvider(self.path).run("prompt", "session-1")

    def test_new_and_resumed_requests_leave_settings_to_each_cli(self):
        def fake_execute(command, prompt, workspace, **kwargs):
            self.assertEqual(kwargs, {})
            self.assertEqual(workspace, self.path)
            for flag in ["--model", "--config", "--effort", "--thinking", "--settings",
                         "--permission-mode", "--enable", "--extension"]:
                self.assertNotIn(flag, command)
            if command[0] == "codex":
                Path(command[command.index("-o") + 1]).write_text("answer")
                return completed('{"type":"thread.started","thread_id":"session-1"}\n')
            if command[0] == "claude":
                self.assertEqual(command, ["claude", "-p", "--output-format", "json"]
                                 + (["--resume", session] if session else []))
                return completed(json.dumps({"session_id": "session-1", "result": "answer"}))
            self.assertEqual(command, ["pi", "--mode", "json", "-p"]
                             + (["--session", session] if session else []))
            return completed(pi_events("session-1", "answer"))
        with patch.object(providers.shutil, "which", return_value="/bin/cli"):
            with patch.object(providers, "execute", side_effect=fake_execute):
                for name in ["codex", "claude", "pi"]:
                    adapter = providers.provider_for(name, self.path, self.path)
                    for session in [None, "session-1"]:
                        with self.subTest(provider=name, session=session):
                            self.assertEqual(adapter.run("prompt", session), ("session-1", "answer"))

    def test_pi_resumes_exact_session(self):
        with patch.object(providers, "execute",
                          return_value=completed(pi_events("session-1", "Follow-up"))) as execute:
            session, answer = providers.PiProvider(self.path).run("prompt", "session-1")
        command = execute.call_args.args[0]
        self.assertEqual(command[command.index("--session") + 1], "session-1")
        self.assertEqual((session, answer), ("session-1", "Follow-up"))

    def test_pi_keeps_unicode_line_separator_inside_json_string(self):
        answer = "first\u2028second"
        events = pi_events("session-1", answer).replace("\\u2028", "\u2028")
        with patch.object(providers, "execute", return_value=completed(events)):
            self.assertEqual(providers.PiProvider(self.path).run("prompt", None),
                             ("session-1", answer))

    def test_pi_rejects_different_or_incomplete_session(self):
        with patch.object(providers, "execute",
                          return_value=completed(pi_events("other", "answer"))):
            with self.assertRaisesRegex(RuntimeError, "different session"):
                providers.PiProvider(self.path).run("prompt", "session-1")
        with patch.object(providers, "execute",
                          return_value=completed(pi_events("session-1", "partial", settled=False))):
            with self.assertRaisesRegex(RuntimeError, "did not complete"):
                providers.PiProvider(self.path).run("prompt", None)

    def test_pi_cli_failure_is_reported(self):
        with patch.object(providers, "execute",
                          return_value=completed("", returncode=1, stderr="model unavailable")):
            with self.assertRaisesRegex(RuntimeError, "model unavailable"):
                providers.PiProvider(self.path).run("prompt", None)


if __name__ == "__main__":
    unittest.main()
