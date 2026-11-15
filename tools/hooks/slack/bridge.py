#!/usr/bin/env python3
"""Configure or run the local command bridge for the Slack browser hook."""
import argparse
import json
import os
import signal
import sys
from pathlib import Path

from local.config import load
from local.runtime import Runtime
from local.server import Server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['init', 'serve', 'install'])
    parser.add_argument('--config', type=Path, default=Path('~/.config/browser-hooks/slack.json'))
    parser.add_argument('--state', type=Path, default=Path('~/.local/state/browser-hooks/slack'))
    parser.add_argument('--workspace', type=Path, default=Path.cwd())
    parser.add_argument('--keyword', default='hook')
    parser.add_argument('--agent', choices=['codex', 'claude'], default='codex')
    args = parser.parse_args()
    os.umask(0o077)
    config_path = args.config.expanduser().resolve()
    checkout = Path(__file__).resolve().parent
    if args.action == 'init':
        config_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        wrapper = str(checkout / 'agents' / f'{args.agent}.py')
        config = {'workspace': str(args.workspace.expanduser().resolve()), 'projects': {},
                  'commands': {args.keyword: {'start': [sys.executable, wrapper], 'resume': [sys.executable, wrapper, '{session_id}']}},
                  'timeout_seconds': 600}
        # Never replace an existing personal configuration.
        with config_path.open('x') as file:
            json.dump(config, file, indent=2)
            file.write('\n')
        print(f'Created {config_path}. Edit commands/projects there, then run serve.')
        return
    state = args.state.expanduser().resolve()
    if checkout.is_relative_to(state) or state.is_relative_to(checkout.parents[2]):
        raise ValueError('Keep private state outside the public repository')
    config = load(config_path)
    if args.action == 'install':
        from local.service import install
        install(checkout / 'bridge.py', config_path, state)
        return
    runtime = Runtime(config, state)
    try:
        server = Server(('127.0.0.1', 19736), runtime, state)
        def stop(*_):
            raise KeyboardInterrupt
        previous = signal.signal(signal.SIGTERM, stop)
        try:
            print(f'Slack browser bridge listening on 127.0.0.1:{server.server_port}', flush=True)
            print('Keywords: ' + ', '.join(config['commands']), flush=True)
            print(f'Pairing code (enter in Browser Hooks): {server.pair_code}', flush=True)
            server.serve_forever(poll_interval=0.2)
        except KeyboardInterrupt:
            pass
        finally:
            signal.signal(signal.SIGTERM, previous)
            server.server_close()
    finally:
        runtime.close()


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(f'Slack hook: {error}', file=sys.stderr)
        raise SystemExit(1)
