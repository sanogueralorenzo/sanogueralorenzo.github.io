"""Run the Slack adapter behind the shared Browser Hooks CLI."""
import signal

from .config import load
from .runtime import Runtime
from .server import Server


def serve(home):
    folder = home / 'hooks/slack'
    config = load(folder / 'config.json')
    runtime = Runtime(config, folder)
    try:
        server = Server(('127.0.0.1', 19736), runtime, home)
        def stop(*_):
            raise KeyboardInterrupt
        previous = signal.signal(signal.SIGTERM, stop)
        try:
            print(f'Slack browser bridge listening on 127.0.0.1:{server.server_port}', flush=True)
            print('Keywords: ' + ', '.join(config['commands']), flush=True)
            # SIGTERM/KeyboardInterrupt wake the blocking selector; no idle shutdown polling.
            server.serve_forever(poll_interval=None)
        except KeyboardInterrupt:
            pass
        finally:
            signal.signal(signal.SIGTERM, previous)
            server.server_close()
    finally:
        runtime.close()
