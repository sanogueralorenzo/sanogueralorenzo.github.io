"""Normalize Codex's final answer, session ID, and safe failures."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from local.errors import HookError, classify, report


def run():
    if len(sys.argv) > 2:
        raise HookError('invalid_response', 'Codex')
    with tempfile.TemporaryDirectory(prefix='slack-hook-codex-') as directory:
        answer_path = Path(directory) / 'answer'
        common = ['--json', '-o', str(answer_path), '--skip-git-repo-check']
        command = (['codex', 'exec', 'resume', *common, sys.argv[1], '-'] if len(sys.argv) == 2
                   else ['codex', 'exec', *common, '-C', os.getcwd(), '-'])
        try:
            result = subprocess.run(command, input=sys.stdin.read(), capture_output=True, text=True)
        except FileNotFoundError:
            raise HookError('missing_cli', 'Codex') from None
        if result.returncode:
            raise classify(result.stdout + '\n' + result.stderr, 'Codex')
        events = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
        session = next((e.get('thread_id') for e in events if e.get('type') == 'thread.started'), None)
        if not answer_path.exists():
            raise HookError('invalid_response', 'Codex')
        print(json.dumps({'session_id': session, 'answer': answer_path.read_text()}))


if __name__ == '__main__':
    try:
        run()
    except (OSError, ValueError, RuntimeError) as error:
        raise SystemExit(report(error))
