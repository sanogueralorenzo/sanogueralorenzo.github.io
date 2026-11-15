"""Bounded subprocess groups, with cancellation and no shell interpolation."""
import json
import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path


def kill(process):
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def execute(command, prompt, workspace, session_id, timeout, cancel):
    args = command['resume' if session_id else 'start']
    args = [session_id if arg == '{session_id}' else arg for arg in args]
    env = {k: v for k, v in os.environ.items() if not k.startswith(('SLACK_', 'AGENT_SLACK_', 'BROWSER_HOOKS_'))}
    with tempfile.TemporaryDirectory(prefix='slack-hook-command-') as folder:
        root = Path(folder)
        (root / 'input').write_text(prompt)
        with (root / 'input').open('rb') as stdin, (root / 'output').open('wb') as stdout, (root / 'error').open('wb') as stderr:
            process = subprocess.Popen(args, cwd=workspace, env=env, stdin=stdin, stdout=stdout, stderr=stderr, start_new_session=True)
            try:
                deadline = time.monotonic() + timeout
                while process.poll() is None:
                    if cancel.is_set() or time.monotonic() >= deadline:
                        raise RuntimeError('Command cancelled or timed out')
                    if max((root / 'output').stat().st_size, (root / 'error').stat().st_size) > 1024 * 1024:
                        raise RuntimeError('Command output exceeded 1 MiB')
                    cancel.wait(0.05)
                if process.returncode:
                    raise RuntimeError(f'Command failed (exit {process.returncode})')
            finally:
                kill(process)
        if (root / 'output').stat().st_size > 1024 * 1024:
            raise RuntimeError('Command output exceeded 1 MiB')
        value = json.loads((root / 'output').read_text())
        if not isinstance(value, dict):
            raise ValueError('Command must return a JSON object')
        returned, answer = value.get('session_id'), value.get('answer')
        if not isinstance(returned, str) or not 1 <= len(returned) <= 200 or not returned.strip():
            raise ValueError('Command returned no session ID')
        if session_id and returned != session_id:
            raise ValueError('Command resumed a different session')
        if not isinstance(answer, str) or not answer.strip() or len(answer) > 12000:
            raise ValueError('Command answer must contain 1–12000 characters')
        return returned, answer.strip()
