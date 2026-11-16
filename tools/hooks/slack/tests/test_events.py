"""Exercise the real loopback WebSocket transport, not a mocked browser socket."""
import base64
import http.client
import json
import os
from pathlib import Path
import socket
import struct
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from local.config import load
from local.runtime import Runtime
from local.server import Server

ORIGIN = 'chrome-extension://' + 'a' * 32
TOKEN = 'synthetic-private-token'


class Client:
    def __init__(self, server, origin=ORIGIN, host=None, key=None):
        self.socket = socket.create_connection(server.server_address, timeout=3)
        self.file = self.socket.makefile('rb')
        key = key or base64.b64encode(os.urandom(16)).decode()
        headers = (f'GET /events HTTP/1.1\r\nHost: {host or f"127.0.0.1:{server.server_port}"}\r\n'
                   f'Origin: {origin}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                   f'Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\n\r\n')
        self.socket.sendall(headers.encode())
        self.response = self.file.readline().decode().strip()
        while self.file.readline() not in (b'\r\n', b''):
            pass

    def send(self, value, opcode=1):
        payload = json.dumps(value).encode() if opcode == 1 else value
        mask = os.urandom(4)
        header = bytes([0x80 | opcode])
        header += bytes([0x80 | len(payload)]) if len(payload) < 126 else b'\xfe' + struct.pack('!H', len(payload))
        self.socket.sendall(header + mask + bytes(value ^ mask[i % 4] for i, value in enumerate(payload)))

    def receive(self):
        header = self.file.read(2)
        if not header:
            return None
        opcode, length = header[0] & 15, header[1]
        if length == 126:
            length = struct.unpack('!H', self.file.read(2))[0]
        payload = self.file.read(length)
        return json.loads(payload) if opcode == 1 else (opcode, payload)

    def close(self):
        self.file.close()
        self.socket.close()


class EventTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        config = self.root / 'config.json'
        script = ('import json,sys; prompt=sys.stdin.read(); '
                  'sys.exit(1) if "FAIL" in prompt else None; '
                  'print(json.dumps({"session_id":"synthetic-session","answer":"answer"}))')
        command = [sys.executable, '-c', script]
        config.write_text(json.dumps({'workspace': str(self.root), 'commands': {'chat': {'start': command, 'resume': command + ['{session_id}']}}}))
        self.runtime = Runtime(load(config), self.root / 'state')
        credentials = self.root / 'hooks/slack/pairing.json'
        credentials.parent.mkdir(parents=True)
        credentials.write_text(json.dumps({'origin': ORIGIN, 'token': TOKEN}))
        self.server = Server(('127.0.0.1', 0), self.runtime, self.root)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.clients = []

    def tearDown(self):
        for client in self.clients:
            client.close()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.runtime.close()
        self.temp.cleanup()

    def client(self, **kwargs):
        client = Client(self.server, **kwargs)
        self.clients.append(client)
        return client

    def authenticated(self):
        client = self.client()
        self.assertTrue(client.response.startswith('HTTP/1.1 101'))
        client.send({'type': 'authenticate', 'token': TOKEN})
        self.assertEqual(client.receive(), {'type': 'settings', 'keywords': ['chat']})
        return client

    def event(self, text='chat ping'):
        return {'team': 'ETEST', 'user': 'UTEST', 'channel': 'CTEST', 'ts': '2000000001.000001',
                'thread_ts': '2000000001.000001', 'text': text, 'messages': []}

    def test_upgrade_rejects_web_pages_other_extensions_rebinding_and_invalid_keys(self):
        for kwargs, status in [({'origin': 'https://app.slack.com'}, 403),
                               ({'origin': 'chrome-extension://' + 'b' * 32}, 403),
                               ({'host': 'evil.example'}, 403), ({'key': 'invalid'}, 400)]:
            client = self.client(**kwargs)
            self.assertIn(f' {status} ', client.response)

    def test_no_events_are_sent_before_first_frame_authentication(self):
        for value in [{'type': 'ping'}, {'type': 'authenticate', 'token': 'wrong'},
                      {'type': 'authenticate', 'token': 'non-ascii-\u2603'}, []]:
            client = self.client()
            client.send(value)
            self.assertIsNone(client.receive())
        self.assertFalse(self.runtime.listeners)

    def test_completed_job_is_pushed_and_transport_keepalives_do_not_query_jobs(self):
        client = self.authenticated()
        client.send({'type': 'ping'})
        self.assertEqual(client.receive(), {'type': 'pong'})
        client.send(b'heartbeat', opcode=9)
        self.assertEqual(client.receive(), (10, b'heartbeat'))
        job = self.runtime.submit(self.event())['job']
        self.assertEqual(client.receive(), {'type': 'job', 'job': job})
        self.assertEqual(self.runtime.status(job)['answer'], 'answer')

    def test_failure_and_cancellation_are_pushed(self):
        client = self.authenticated()
        with self.assertLogs(level='ERROR'):
            job = self.runtime.submit(self.event('chat FAIL'))['job']
            self.assertEqual(client.receive(), {'type': 'job', 'job': job})
        self.assertEqual(self.runtime.status(job)['status'], 'failed')
        self.runtime.cancel(job)
        self.assertEqual(client.receive(), {'type': 'job', 'job': job})

    def test_unmasked_binary_and_oversized_frames_close_the_stream(self):
        for frame in [b'\x81\x02{}', b'\x82\x80aaaa', b'\x81\xfe\xff\xff']:
            client = self.authenticated()
            client.socket.sendall(frame)
            self.assertIsNone(client.receive())

    def test_shutdown_unsubscribes_and_closes_active_connections(self):
        client = self.authenticated()
        self.assertEqual(len(self.runtime.listeners), 1)
        self.server.server_close()
        self.assertIsNone(client.receive())
        self.assertFalse(self.runtime.listeners)

    def test_pair_rotation_disconnects_the_previous_authenticated_stream(self):
        client = self.authenticated()
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=3)
        try:
            connection.request('POST', '/pair', json.dumps({'code': self.server.pair_code}), {
                'Content-Type': 'application/json', 'X-Browser-Hooks-Origin': ORIGIN})
            response = connection.getresponse()
            self.assertEqual(response.status, 200)
            self.assertNotEqual(json.loads(response.read())['token'], TOKEN)
        finally:
            connection.close()
        self.assertIsNone(client.receive())
        self.assertFalse(self.runtime.listeners)


if __name__ == '__main__':
    unittest.main()
