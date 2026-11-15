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
from local import paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['install', 'serve', 'status'])
    parser.add_argument('--config', type=Path, default=paths.config_path())
    parser.add_argument('--state', type=Path, default=paths.state_root())
    parser.add_argument('--data', type=Path, default=paths.data_root())
    parser.add_argument('--workspace', type=Path, default=Path.cwd())
    args = parser.parse_args()
    os.umask(0o077)
    config_path = args.config.expanduser().resolve()
    checkout = Path(__file__).resolve().parent
    state = args.state.expanduser().resolve()
    data = args.data.expanduser().resolve()
    if checkout.is_relative_to(state) or any(path.is_relative_to(checkout.parents[2]) for path in [state, config_path, data]):
        raise ValueError('Keep private state, data and configuration outside the public repository')
    if state.is_relative_to(data) or data.is_relative_to(state):
        raise ValueError('Keep data and state in separate directories')
    if args.action == 'install':
        from local.setup import setup
        setup(config_path, state, data, checkout, args.workspace)
        return
    if args.action == 'status':
        from local.setup import status
        raise SystemExit(status(config_path, state, data))
    config = load(config_path)
    runtime = Runtime(config, state)
    try:
        server = Server(('127.0.0.1', 19736), runtime, data)
        def stop(*_):
            raise KeyboardInterrupt
        previous = signal.signal(signal.SIGTERM, stop)
        try:
            print(f'Slack browser bridge listening on 127.0.0.1:{server.server_port}', flush=True)
            print('Keywords: ' + ', '.join(config['commands']), flush=True)
            if not server.paired:
                print('Run slack-hook install, then load or reload the printed extension folder to pair automatically.', flush=True)
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
