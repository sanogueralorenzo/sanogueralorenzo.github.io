"""One-command setup, pairing instructions, and local health checks."""
import json
from pathlib import Path
import shutil
import sys
import time
from http.client import HTTPConnection, HTTPException

from .config import load
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


def setup(home, checkout, workspace):
    folder = home / 'hooks/slack'
    config = configure(folder / 'config.json', checkout / 'slack', workspace)
    install(checkout / 'cli.py', home)
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if health():
            break
        time.sleep(0.1)
    else:
        raise RuntimeError(f'Bridge did not start. Check {folder / "logs/bridge.log"}')
    print('Slack is ready. Keywords: ' + ' / '.join(config['commands']))
    print(f'Configuration: {folder / "config.json"}')
    print('Slack attaches automatically. Keep one Slack tab open; no listening toggle.')


def status(home):
    folder = home / 'hooks/slack'
    config = load(folder / 'config.json')
    result = health()
    print('Slack bridge: ' + ('running' if result else 'not running; rerun the installer'))
    print('Browser: ' + ('paired' if result and result['paired'] else 'not paired; rerun the installer, then load or reload the printed extension folder'))
    print('Keywords: ' + ' / '.join(config['commands']))
    print(f'Configuration: {folder / "config.json"}')
    print(f'Logs: {folder / "logs/bridge.log"}')
    print(f'Extension folder: {home / "extension"}')
    for name in ['codex', 'claude']:
        if any(str(Path(arg).name) == f'{name}.py' for entry in config['commands'].values() for arg in entry['start']):
            print(name + ': ' + ('installed (login checked when a request runs)' if shutil.which(name) else 'not found; install the CLI and rerun the installer'))
    if result and result.get('error'):
        print('Last request: ' + result['error']['message'])
    return 0 if result and result['paired'] else 1
