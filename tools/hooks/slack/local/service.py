"""Run the command bridge at login on macOS."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys

LABEL = 'dev.browser-hooks.slack'


def specification(python, bridge, config, state):
    return {
        'Label': LABEL,
        'ProgramArguments': [str(python), str(bridge), 'serve', '--config', str(config), '--state', str(state)],
        'RunAtLoad': True, 'KeepAlive': True,
        'WorkingDirectory': str(bridge.parent),
        'EnvironmentVariables': {'PATH': os.environ.get('PATH', '/usr/bin:/bin')},
        'StandardOutPath': str(state / 'bridge.log'),
        'StandardErrorPath': str(state / 'bridge.log'),
        'Umask': 0o077,
        'ThrottleInterval': 10,
    }


def install(bridge, config, state):
    if sys.platform != 'darwin':
        raise ValueError('Automatic service installation supports macOS; use serve on Linux')
    folder = Path.home() / 'Library' / 'LaunchAgents'
    folder.mkdir(parents=True, exist_ok=True)
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    state.chmod(0o700)
    log = state / 'bridge.log'
    log.touch(mode=0o600, exist_ok=True)
    log.chmod(0o600)
    path = folder / f'{LABEL}.plist'
    target = f'gui/{os.getuid()}/{LABEL}'
    loaded = subprocess.run(['launchctl', 'print', target], capture_output=True).returncode == 0
    if loaded:
        subprocess.run(['launchctl', 'bootout', target], check=True, capture_output=True)
    path.write_bytes(plistlib.dumps(specification(Path(sys.executable).resolve(), bridge, config, state)))
    path.chmod(0o600)
    result = subprocess.run(['launchctl', 'bootstrap', f'gui/{os.getuid()}', str(path)], capture_output=True)
    if result.returncode:
        raise RuntimeError('Could not start bridge service; inspect launchctl and the private bridge log')
    print(f'Installed {LABEL}. The bridge starts automatically at login.')
    print(f'Pairing code and diagnostics: {log}')
