"""One-command setup, pairing instructions, and local health checks."""
import json
from pathlib import Path
import shutil
import shlex
import sys
import time
from http.client import HTTPConnection, HTTPException

from .config import load
from .extension import prepare
from .service import install


def health():
    connection = HTTPConnection('127.0.0.1', 19736, timeout=1)
    try:
        connection.request('GET', '/health')
        response = connection.getresponse()
        value = json.loads(response.read())
        return value if response.status == 200 and value.get('service') == 'browser-hooks-slack' else None
    except (OSError, ValueError, HTTPException):
        return None
    finally:
        connection.close()


def configure(path, checkout, workspace):
    if path.exists():
        return load(path)
    commands = {}
    for keyword, agent in [('chat', 'codex'), ('claude', 'claude')]:
        if shutil.which(agent):
            wrapper = str(checkout / 'agents' / f'{agent}.py')
            commands[keyword] = {'start': [sys.executable, wrapper], 'resume': [sys.executable, wrapper, '{session_id}']}
    if not commands:
        raise ValueError('Install and sign in to Codex or Claude first, then rerun the installer.')
    workspace = workspace.expanduser().resolve()
    if not workspace.is_dir():
        raise ValueError('Choose an existing directory with --workspace /path/to/project.')
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open('x') as file:
        json.dump({'workspace': str(workspace), 'projects': {}, 'commands': commands, 'timeout_seconds': 600}, file, indent=2)
        file.write('\n')
    path.chmod(0o600)
    return load(path)


def launcher(path, state, checkout):
    target = Path.home() / '.local/bin/slack-hook'
    target.parent.mkdir(parents=True, exist_ok=True)
    command = ' '.join(shlex.quote(str(arg)) for arg in [sys.executable, checkout / 'bridge.py'])
    options = ' '.join(shlex.quote(str(arg)) for arg in ['--config', path, '--state', state])
    target.write_text('#!/bin/sh\nexec ' + command + ' "$@" ' + options + '\n')
    target.chmod(0o700)
    return target


def setup(path, state, checkout, workspace):
    config = configure(path, checkout, workspace)
    extension = prepare(checkout, state)
    install(checkout / 'bridge.py', path, state)
    deadline = time.monotonic() + 8
    result = None
    while time.monotonic() < deadline:
        result = health()
        if result:
            break
        time.sleep(0.1)
    if not result:
        raise RuntimeError(f'Bridge did not start. check {state / "bridge.log"}')
    executable = launcher(path, state, checkout)
    print('Slack browser listener is ready. Keywords: ' + ' / '.join(config['commands']))
    print(f'Configuration: {path}')
    print(f'Extension folder: {extension}')
    if result['paired']:
        print('Existing browser pairing, settings and agent sessions were preserved.')
        print('After an extension update, reload Browser Hooks once, then reload Slack.')
    else:
        print('1. Load the extension folder in Edge/Chrome (Developer mode → Load unpacked).')
        print('2. Pairing happens automatically when the extension loads; no code to copy.')
        print('3. Open Slack and send: ' + next(iter(config['commands'])) + ' your request')
    print('Load or reload this private extension folder within ten minutes; rerun the installer if needed.')
    print('Check status: ' + (str(executable) if not shutil.which('slack-hook') else 'slack-hook') + ' status')
    print('Slack attaches automatically. Keep one Slack tab open; no listening toggle.')


def status(path, state):
    config = load(path)
    result = health()
    print('Bridge: ' + ('running' if result else 'not running; rerun the installer'))
    print('Browser: ' + ('paired' if result and result['paired'] else 'not paired; rerun the installer, then load or reload the printed extension folder'))
    print('Keywords: ' + ' / '.join(config['commands']))
    print(f'Configuration: {path}')
    print(f'Logs: {state / "bridge.log"}')
    for name in ['codex', 'claude']:
        if any(str(Path(arg).name) == f'{name}.py' for entry in config['commands'].values() for arg in entry['start']):
            print(name + ': ' + ('installed (login checked when a request runs)' if shutil.which(name) else 'not found; install the CLI and rerun the installer'))
    if result and result.get('error'):
        print('Last request: ' + result['error']['message'])
    return 0 if result and result['paired'] else 1
