"""Run the real Rust bridge against disposable, synthetic data."""

import base64, functools, http.client, json, logging, os, select, signal, socket, sqlite3, struct, subprocess, sys, tempfile, time
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
ORIGIN = "chrome-extension://" + "a" * 32


@functools.lru_cache(maxsize=1)
def bridge_binary():
    override = os.environ.get("BROWSER_HOOKS_BRIDGE")
    if override:
        return Path(override).resolve()
    manifest = ROOT / "bridge/Cargo.toml"
    result = subprocess.run(
        ["cargo", "build", "--locked", "--manifest-path", str(manifest)],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise RuntimeError(result.stderr)
    target = Path(os.environ.get("CARGO_TARGET_DIR", manifest.parent / "target"))
    return target.resolve() / "debug/browser-hooks-bridge"


class Client:
    def __init__(self, server, origin=ORIGIN, host=None, key=None):
        self.socket = socket.create_connection(server.server_address, timeout=3)
        self.file = self.socket.makefile("rb")
        key = key or base64.b64encode(os.urandom(16)).decode()
        headers = (
            f"GET /events HTTP/1.1\r\nHost: {host or f'127.0.0.1:{server.server_port}'}\r\n"
            f"Origin: {origin}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\n\r\n"
        )
        self.socket.sendall(headers.encode())
        self.response = self.file.readline().decode().strip()
        while self.file.readline() not in (b"\r\n", b""):
            pass

    def send(self, value, opcode=1):
        payload = json.dumps(value).encode() if opcode == 1 else value
        mask = os.urandom(4)
        header = bytes([0x80 | opcode])
        header += (
            bytes([0x80 | len(payload)])
            if len(payload) < 126
            else b"\xfe" + struct.pack("!H", len(payload))
        )
        self.socket.sendall(
            header
            + mask
            + bytes(value ^ mask[i % 4] for i, value in enumerate(payload))
        )

    def receive(self):
        header = self.file.read(2)
        if not header:
            return None
        opcode, length = header[0] & 15, header[1]
        if length == 126:
            length = struct.unpack("!H", self.file.read(2))[0]
        payload = self.file.read(length)
        return json.loads(payload) if opcode == 1 else (opcode, payload)

    def close(self):
        self.file.close()
        self.socket.close()


class Backend:
    def __init__(self, home, config, auto_pair=True, env=None):
        self.home = Path(home)
        self.config = config
        self.env = env
        self.process = None
        self.token = None
        folder = self.home / "hooks/slack"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "config.json").write_text(json.dumps(config))
        self.start(auto_pair)

    def start(self, auto_pair=True):
        args = [str(bridge_binary()), "serve", "--home", str(self.home), "--port", "0"]
        self.stderr = open(self.home / "stderr.log", "a+")
        self.process = subprocess.Popen(
            args, stdout=subprocess.PIPE, stderr=self.stderr, text=True, env=self.env
        )
        try:
            if not select.select([self.process.stdout], [], [], 6)[0]:
                raise RuntimeError("Bridge did not start")
            line = self.process.stdout.readline().strip()
            if "127.0.0.1:" not in line:
                self.stderr.seek(0)
                raise RuntimeError("Bridge startup failed: " + self.stderr.read())
            self.port = int(line.rsplit(":", 1)[-1])
            self.server = SimpleNamespace(
                server_address=("127.0.0.1", self.port), server_port=self.port
            )
            saved = self.home / "pairing.json"
            if saved.exists():
                self.token = json.loads(saved.read_text())["token"]
            if auto_pair:
                status, value, _ = self.call(
                    "POST", "/pair", {"code": self.bootstrap()["code"]}, auth=False
                )
                assert status == 200, (status, value)
                self.token = value["token"]
        except BaseException:
            self.stop()
            raise

    def bootstrap(self):
        return json.loads((self.home / "extension/bridge-pairing.json").read_text())

    def call(self, method, path, body=None, auth=True, headers=None, raw=None):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        base = {"Content-Type": "application/json", "X-Browser-Hooks-Origin": ORIGIN}
        if auth and self.token:
            base["Authorization"] = "Bearer " + self.token
        base.update(headers or {})
        try:
            c.request(
                method,
                path,
                body=raw
                if raw is not None
                else json.dumps(body)
                if body is not None
                else None,
                headers=base,
            )
            r = c.getresponse()
            payload = r.read()
            return (
                r.status,
                json.loads(payload) if payload else None,
                dict(r.getheaders()),
            )
        finally:
            c.close()

    def request(self, method, path, body=None):
        status, value, _ = self.call(method, path, body)
        if status >= 400:
            raise ValueError(str(value))
        return value

    def socket(self, token=None, origin=ORIGIN):
        c = Client(self.server, origin=origin)
        c.send({"type": "authenticate", "token": token or self.token})
        assert c.receive() == {
            "type": "settings",
            "hooks": {"slack": {"keywords": sorted(self.config["commands"])}},
        }
        return c

    def wait(self, job, status="ready", seconds=5):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            value = self.request("GET", "/slack/jobs/" + job)
            if value["status"] == status:
                return value
            time.sleep(0.01)
        raise AssertionError((status, value))

    def stop(self):
        if self.process:
            if self.process.poll() is None:
                self.process.send_signal(signal.SIGTERM)
            try:
                self.process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.communicate()
                raise
            self.process = None
            self.stderr.close()


class RuntimeProxy:
    def __init__(self, config, state_dir):
        state_dir = Path(state_dir)
        state_dir.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(
            prefix="rust-runtime-", dir=state_dir.parent
        )
        home = Path(self.temp.name)
        (home / "hooks").mkdir()
        (home / "hooks/slack").symlink_to(state_dir, target_is_directory=True)
        raw = {
            "workspace": str(config["workspace"]),
            "projects": {k: str(v) for k, v in config["projects"].items()},
            "commands": config["commands"],
            "timeout_seconds": config["timeout"],
        }
        self.backend = Backend(home, raw)
        self.db = sqlite3.connect(state_dir / "sessions.sqlite3")
        self.closed = False

    def submit(self, event):
        return self.backend.request("POST", "/slack/run", event)

    def status(self, job):
        status, value, _ = self.backend.call("GET", "/slack/jobs/" + job)
        if status == 404:
            return None
        if value.get("status") == "failed":
            logging.error("%s", value["error"]["message"])
        return value

    def cancel(self, job):
        return self.backend.request("POST", "/slack/cancel", {"job": job})

    def claim(self, job):
        return self.backend.request("POST", "/slack/claim", {"job": job})

    def delivered(self, job, ts):
        return self.backend.request("POST", "/slack/delivered", {"job": job, "ts": ts})

    def close(self):
        if not self.closed:
            self.backend.stop()
            self.db.close()
            self.temp.cleanup()
            self.closed = True


def event(**extra):
    return {
        "team": "ETEST",
        "user": "UTEST",
        "channel": "CTEST",
        "ts": "2000000001.000001",
        "thread_ts": "2000000001.000001",
        "text": "hook ping",
        "messages": [],
        **extra,
    }


def configuration(home, script=None, timeout=2):
    script = (
        script
        or 'import json,sys;sys.stdin.read();print(json.dumps({"session_id":sys.argv[1] if len(sys.argv)>1 else "synthetic-session","answer":"synthetic answer"}))'
    )
    args = [sys.executable, "-c", script]
    return {
        "workspace": str(home),
        "projects": {},
        "commands": {"hook": {"start": args, "resume": args + ["{session_id}"]}},
        "timeout_seconds": timeout,
    }
