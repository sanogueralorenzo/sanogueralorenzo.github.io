"""Bounded subprocess groups, with cancellation and no shell interpolation."""
import json
import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path

from .errors import HookError, from_response


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
            try:
                process = subprocess.Popen(args, cwd=workspace, env=env, stdin=stdin, stdout=stdout, stderr=stderr, start_new_session=True)
            except FileNotFoundError:
                raise HookError('missing_cli') from None
            try:
                deadline = time.monotonic() + timeout
                while process.poll() is None:
                    if cancel.is_set():
                        raise HookError('cancelled')
                    if time.monotonic() >= deadline:
                        raise HookError('timeout')
                    if max((root / 'output').stat().st_size, (root / 'error').stat().st_size) > 1024 * 1024:
                        raise HookError('output_limit')
                    cancel.wait(0.05)
            finally:
                kill(process)
        if (root / 'output').stat().st_size > 1024 * 1024:
            raise HookError('output_limit')
        try:
            value = json.loads((root / 'output').read_text())
        except ValueError:
            raise HookError('command_failed' if process.returncode else 'invalid_response') from None
        failure = from_response(value)
        if failure:
            raise failure
        if process.returncode:
            raise HookError('command_failed')
        if not isinstance(value, dict):
            raise HookError('invalid_response')
        returned, answer = value.get('session_id'), value.get('answer')
        if not isinstance(returned, str) or not 1 <= len(returned) <= 200 or not returned.strip():
            raise HookError('invalid_response')
        if session_id and returned != session_id:
            raise HookError('session_invalid')
        if not isinstance(answer, str) or not answer.strip() or len(answer) > 12000:
            raise HookError('invalid_response')
        return returned, answer.strip()
