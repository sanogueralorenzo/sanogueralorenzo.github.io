"""Loopback-only HTTP bridge, paired to one browser extension."""
import hmac
import json
import os
import re
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Server(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, runtime, state_dir):
        if address[0] != '127.0.0.1':
            raise ValueError('Bridge must bind to loopback')
        self.runtime = runtime
        self.credentials = state_dir / 'pairing.json'
        self.pair_lock = threading.Lock()
        self.pair_code = secrets.token_urlsafe(24)
        self.pair_deadline = time.monotonic() + 600
        self.pair_file = state_dir / 'extension' / 'bridge-pairing.json'
        self.paired = json.loads(self.credentials.read_text()) if self.credentials.exists() else None
        super().__init__(address, Handler)
        self.pair_file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.pair_file.parent.chmod(0o700)
        with os.fdopen(os.open(self.pair_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as file:
            json.dump({'code': self.pair_code, 'expiresAt': int(time.time() * 1000) + 600_000}, file)


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.0'
    def log_message(self, *args):
        pass

    def respond(self, status, value):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        self.handle_api()

    def do_POST(self):
        self.handle_api()

    def handle_api(self):
        self.connection.settimeout(5)
        origin = self.headers.get('X-Browser-Hooks-Origin', '')
        if self.headers.get('Host') != f'127.0.0.1:{self.server.server_port}':
            return self.respond(403, {'error': 'Loopback host required'})
        if self.path == '/health' and self.command == 'GET':
            return self.respond(200, {'service': 'browser-hooks-slack', 'paired': bool(self.server.paired), 'error': self.server.runtime.last_error})
        browser_origin = self.headers.get('Origin')
        if browser_origin and browser_origin != origin:
            return self.respond(403, {'error': 'Origin mismatch'})
        # Reject DNS rebinding and requests from web pages, including signed-in Slack.
        expected_host = f'127.0.0.1:{self.server.server_port}'
        if self.headers.get('Host') != expected_host or not re.fullmatch(r'chrome-extension://[a-p]{32}', origin):
            return self.respond(403, {'error': 'Extension origin required'})
        body = {}
        try:
            if self.command == 'POST':
                if self.headers.get_content_type() != 'application/json':
                    return self.respond(415, {'error': 'JSON required'})
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 2 * 1024 * 1024:
                    return self.respond(413, {'error': 'Invalid request size'})
                body = json.loads(self.rfile.read(length))
                if not isinstance(body, dict):
                    raise ValueError('Object required')
            if self.path == '/pair' and self.command == 'POST':
                with self.server.pair_lock:
                    code = body.get('code', '')
                    if not isinstance(code, str) or not self.server.pair_code or time.monotonic() > self.server.pair_deadline or not hmac.compare_digest(code, self.server.pair_code):
                        return self.respond(403, {'error': 'Automatic pairing expired. Rerun the installer, then reload Browser Hooks.'})
                    paired = {'origin': origin, 'token': secrets.token_urlsafe(32)}
                    # The private state directory is never inside the public checkout.
                    with os.fdopen(os.open(self.server.credentials, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as file:
                        json.dump(paired, file)
                    self.server.paired = paired
                    self.server.pair_code = None
                    self.server.pair_file.unlink(missing_ok=True)
                    return self.respond(200, paired)
            paired = self.server.paired
            supplied = self.headers.get('Authorization', '')
            if not paired or origin != paired['origin'] or not hmac.compare_digest(supplied, 'Bearer ' + paired['token']):
                return self.respond(403, {'error': 'Browser pairing expired. Rerun the installer, then reload Browser Hooks.'})
            runtime = self.server.runtime
            if self.path == '/config' and self.command == 'GET':
                return self.respond(200, {'keywords': list(runtime.config['commands'])})
            if self.path == '/run' and self.command == 'POST':
                return self.respond(200, runtime.submit(body))
            if self.path.startswith('/jobs/') and self.command == 'GET':
                value = runtime.status(self.path.removeprefix('/jobs/'))
                return self.respond(200 if value else 404, value or {'error': 'Unknown job'})
            if self.path in ('/claim', '/delivered', '/cancel') and self.command == 'POST':
                job = body.get('job', '')
                if not isinstance(job, str) or not re.fullmatch(r'[a-f0-9]{64}', job):
                    raise ValueError('Invalid job')
                if self.path == '/claim':
                    return self.respond(200, runtime.claim(job))
                if self.path == '/delivered':
                    return self.respond(200, runtime.delivered(job, body.get('ts')))
                return self.respond(200, runtime.cancel(job))
            self.respond(404, {'error': 'Unknown endpoint'})
        except (ValueError, KeyError, TypeError, TimeoutError):
            self.respond(400, {'error': 'Invalid request or configuration'})
        except Exception:
            self.respond(500, {'error': 'Local bridge failed; check its terminal'})
