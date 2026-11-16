"""Small authenticated, push-only WebSocket channel for extension events."""
import base64
import hashlib
import hmac
import json
import queue
import re
import socket
import struct
import threading


class Peer:
    def __init__(self, handler):
        self.handler = handler
        self.socket = handler.connection
        self.outbox = queue.Queue(maxsize=128)
        self.closed = threading.Event()
        self.unsubscribe = lambda: None

    def receive(self):
        def read(size):
            value = self.handler.rfile.read(size)
            if len(value) != size:
                raise ConnectionError('Closed event stream')
            return value
        first, second = read(2)
        opcode = first & 15
        # Our browser sends small, final, masked frames without extensions.
        if first & 0x70 or not first & 0x80 or not second & 0x80 or opcode not in (1, 8, 9, 10):
            raise ValueError('Invalid event frame')
        length = second & 127
        if length == 126:
            length = struct.unpack('!H', read(2))[0]
        elif length == 127:
            raise ValueError('Event frame too large')
        if length > 4096 or opcode >= 8 and length > 125:
            raise ValueError('Event frame too large')
        mask = read(4)
        payload = bytes(value ^ mask[i % 4] for i, value in enumerate(read(length)))
        return opcode, payload

    def publish(self, value):
        if self.closed.is_set():
            return
        try:
            self.outbox.put_nowait((1, json.dumps(value).encode()))
        except queue.Full:
            self.close()

    def write(self):
        try:
            while not self.closed.is_set():
                item = self.outbox.get()
                if item is None:
                    return
                opcode, payload = item
                header = bytes([0x80 | opcode])
                header += bytes([len(payload)]) if len(payload) < 126 else b'\x7e' + struct.pack('!H', len(payload))
                self.socket.sendall(header + payload)
        except OSError:
            self.close()

    def close(self):
        if self.closed.is_set():
            return
        self.closed.set()
        self.unsubscribe()
        try:
            self.socket.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        try:
            self.outbox.put_nowait(None)
        except queue.Full:
            pass


def stream(handler):
    server = handler.server
    origin = handler.headers.get('Origin', '')
    paired = server.paired
    if not paired or origin != paired['origin'] or not re.fullmatch(r'chrome-extension://[a-p]{32}', origin):
        return handler.respond(403, {'error': 'Paired extension required'})
    try:
        key = handler.headers.get('Sec-WebSocket-Key', '')
        if len(base64.b64decode(key, validate=True)) != 16:
            raise ValueError()
        if handler.headers.get('Upgrade', '').lower() != 'websocket' or handler.headers.get('Sec-WebSocket-Version') != '13':
            raise ValueError()
        if 'upgrade' not in [part.strip().lower() for part in handler.headers.get('Connection', '').split(',')]:
            raise ValueError()
    except (ValueError, TypeError):
        return handler.respond(400, {'error': 'Invalid event upgrade'})
    handler.protocol_version = 'HTTP/1.1'
    handler.send_response(101)
    handler.send_header('Upgrade', 'websocket')
    handler.send_header('Connection', 'Upgrade')
    handler.send_header('Sec-WebSocket-Accept', base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode())
    handler.end_headers()
    handler.wfile.flush()
    peer = Peer(handler)
    registered = False
    try:
        # Tokens never enter URLs, page messages, or unauthenticated event data.
        handler.connection.settimeout(5)
        opcode, payload = peer.receive()
        auth = json.loads(payload) if opcode == 1 else {}
        if not isinstance(auth, dict) or auth.get('type') != 'authenticate' or not isinstance(auth.get('token'), str) or not hmac.compare_digest(auth['token'].encode(), paired['token'].encode()):
            return
        with server.peers_lock:
            if server.paired is not paired or server.closing:
                return
            peer.unsubscribe = server.runtime.subscribe(peer.publish)
            server.peers.add(peer)
            registered = True
        peer.publish({'type': 'settings', 'keywords': list(server.runtime.config['commands'])})
        writer = threading.Thread(target=peer.write, daemon=True)
        writer.start()
        handler.connection.settimeout(45)
        while not peer.closed.is_set() and server.paired is paired:
            opcode, payload = peer.receive()
            if opcode == 8:
                break
            if opcode == 9:
                peer.outbox.put_nowait((10, payload))
            elif opcode == 1:
                if json.loads(payload) != {'type': 'ping'}:
                    break
                peer.publish({'type': 'pong'})
    except (OSError, ValueError, ConnectionError, queue.Full):
        pass
    finally:
        peer.close()
        if registered:
            with server.peers_lock:
                server.peers.discard(peer)
        handler.close_connection = True
