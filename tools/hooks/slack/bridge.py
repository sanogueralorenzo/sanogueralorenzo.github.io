#!/usr/bin/env python3
"""Configure or run the local command bridge for the Slack browser hook."""
import argparse
import os
import signal
import sys
from pathlib import Path

from local.config import load
from local.runtime import Runtime
from local.server import Server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['install', 'serve', 'status'])
    parser.add_argument('--config', type=Path, default=Path('~/.config/browser-hooks/slack.json'))
    parser.add_argument('--state', type=Path, default=Path('~/.local/state/browser-hooks/slack'))
    parser.add_argument('--workspace', type=Path, default=Path.cwd())
    args = parser.parse_args()
    os.umask(0o077)
    config_path = args.config.expanduser().resolve()
    checkout = Path(__file__).resolve().parent
    state = args.state.expanduser().resolve()
    if checkout.is_relative_to(state) or state.is_relative_to(checkout.parents[2]):
        raise ValueError('Keep private state outside the public repository')
    if args.action == 'install':
        from local.setup import setup
        setup(config_path, state, checkout, args.workspace)
        return
    if args.action == 'status':
        from local.setup import status
        raise SystemExit(status(config_path, state))
    config = load(config_path)
    runtime = Runtime(config, state)
    try:
        server = Server(('127.0.0.1', 19736), runtime, state)
        def stop(*_):
            raise KeyboardInterrupt
        previous = signal.signal(signal.SIGTERM, stop)
        try:
            print(f'Slack browser bridge listening on 127.0.0.1:{server.server_port}', flush=True)
            print('Keywords: ' + ', '.join(config['commands']), flush=True)
            if not server.paired:
                print('Run bridge.py install to display your pairing code.', flush=True)
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
