"""Local CLI providers with a common (session ID, final answer) result."""

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Protocol


class Provider(Protocol):
    name: str

    def run(self, prompt: str, session_id: str | None) -> tuple[str, str]: ...


def require_available(name):
    if name not in {"codex", "claude"}:
        raise ValueError(f"Unknown provider: {name}")
    if not shutil.which(name):
        raise RuntimeError(f"{name} CLI is not installed or is not on PATH")


def execute(command, prompt, workspace):
    return subprocess.run(
        command, input=prompt, text=True, capture_output=True, cwd=workspace,
        check=False,
        env={key: value for key, value in os.environ.items() if not key.startswith("SLACK_")},
    )


def check_session(name, returned, expected):
    if not returned:
        raise RuntimeError(f"{name} CLI did not return a session ID; cannot resume this thread")
    if expected and returned != expected:
        raise RuntimeError(f"{name} CLI resumed a different session; refusing to replace the thread session")


class CodexProvider:
    name = "codex"

    def __init__(self, workspace, state_dir):
        self.workspace = workspace
        self.state_dir = state_dir
        self.model = os.environ.get("CODEX_MODEL", "gpt-6-luna").strip()
        self.effort = os.environ.get("CODEX_REASONING_EFFORT", "high").strip()
        if self.effort not in {"none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"}:
            raise ValueError("CODEX_REASONING_EFFORT is not a recognized effort value")

    def run(self, prompt, session_id):
        with tempfile.NamedTemporaryFile(dir=self.state_dir, prefix="answer-", delete=False) as output:
            answer_path = Path(output.name)
        try:
            common = [
                "--json", "-m", self.model, "-c", f'model_reasoning_effort="{self.effort}"',
                "-c", 'approval_policy="never"', "-o", str(answer_path),
                "--skip-git-repo-check",
            ]
            if session_id:
                command = ["codex", "exec", "resume", *common,
                           "-c", 'sandbox_mode="workspace-write"', session_id, "-"]
            else:
                command = ["codex", "exec", *common, "--sandbox", "workspace-write",
                           "-C", str(self.workspace), "-"]
            result = execute(command, prompt, self.workspace)
            if result.returncode:
                raise RuntimeError(f"codex exec failed (exit {result.returncode}): {result.stderr[-1500:]}")
            started = []
            for line in result.stdout.splitlines():
                if line.startswith("{"):
                    item = json.loads(line)
                    if item.get("type") == "thread.started":
                        started.append(item.get("thread_id"))
            new_session_id = next((value for value in started if value), None)
            check_session(self.name, new_session_id, session_id)
            answer = answer_path.read_text().strip()
            if not answer:
                raise RuntimeError("codex exec returned an empty final answer")
            return new_session_id, answer
        finally:
            answer_path.unlink(missing_ok=True)


class ClaudeProvider:
    name = "claude"

    def __init__(self, workspace):
        self.workspace = workspace
        self.model = os.environ.get("CLAUDE_MODEL", "").strip()
        self.effort = os.environ.get("CLAUDE_REASONING_EFFORT", "").strip()
        if self.effort and self.effort not in {"low", "medium", "high", "xhigh", "max"}:
            raise ValueError("CLAUDE_REASONING_EFFORT must be low, medium, high, xhigh, or max")

    def run(self, prompt, session_id):
        command = ["claude", "-p", "--output-format", "json",
                   "--permission-mode", "acceptEdits"]
        if self.model:
            command.extend(["--model", self.model])
        if self.effort:
            command.extend(["--effort", self.effort])
        if session_id:
            command.extend(["--resume", session_id])
        result = execute(command, prompt, self.workspace)
        try:
            response = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            raise RuntimeError(f"claude CLI did not return JSON: {result.stderr[-1500:]}") from error
        if result.returncode or response.get("is_error"):
            detail = response.get("result") or result.stderr[-1500:]
            raise RuntimeError(f"claude CLI failed (exit {result.returncode}): {detail}")
        new_session_id = response.get("session_id")
        check_session(self.name, new_session_id, session_id)
        answer = response.get("result")
        if not isinstance(answer, str) or not answer.strip():
            raise RuntimeError("claude CLI returned an empty final answer")
        return new_session_id, answer.strip()


def provider_for(name, workspace, state_dir) -> Provider:
    require_available(name)
    if name == "codex":
        return CodexProvider(workspace, state_dir)
    return ClaudeProvider(workspace)
