"""Run one Codex turn, releasing its app-server before returning the reply."""

from collections import deque
import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
from uuid import UUID

from errors import HookError, classify, report


class AppServer:
    def __init__(self):
        self.stderr = tempfile.TemporaryFile(mode="w+")
        try:
            self.process = subprocess.Popen(
                ["codex", "app-server", "--listen", "stdio://"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=self.stderr,
                text=True,
            )
        except OSError as error:
            self.stderr.close()
            raise HookError(
                "missing_cli" if isinstance(error, FileNotFoundError) else "command_failed",
                "Codex",
            ) from None
        self.incoming = queue.Queue(maxsize=128)
        self.events = deque()
        self.serial = 0
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()

    def read(self):
        try:
            while line := self.process.stdout.readline(1024 * 1024 + 1):
                if len(line) > 1024 * 1024:
                    raise HookError("output_limit", "Codex")
                message = json.loads(line)
                if not isinstance(message, dict):
                    raise ValueError("Invalid RPC message")
                if "id" in message or message.get("method") in (
                    "item/completed",
                    "turn/completed",
                ):
                    self.incoming.put(message)
        except (OSError, ValueError, HookError) as error:
            self.incoming.put(error)
        finally:
            self.incoming.put(None)

    def send(self, message):
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()

    def receive(self, timeout=None):
        try:
            message = self.incoming.get(timeout=timeout)
        except queue.Empty:
            raise HookError("timeout", "Codex") from None
        if message is None:
            self.stderr.seek(0, os.SEEK_END)
            self.stderr.seek(max(0, self.stderr.tell() - 65536))
            raise classify(self.stderr.read(), "Codex")
        if isinstance(message, Exception):
            raise message
        if "id" in message and "method" in message:
            raise HookError("permission_required", "Codex")
        return message

    def request(self, method, params):
        self.serial += 1
        request_id = self.serial
        self.send({"id": request_id, "method": method, "params": params})
        while True:
            message = self.receive(timeout=30)
            if message.get("id") == request_id:
                if "error" in message:
                    raise classify(json.dumps(message["error"]), "Codex")
                return message["result"]
            self.events.append(message)

    def close(self):
        try:
            try:
                self.process.stdin.close()
            except BrokenPipeError:
                pass
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
        finally:
            self.process.stdout.close()
            self.stderr.close()


def run():
    if len(sys.argv) > 2:
        raise HookError("invalid_response", "Codex")
    prompt = sys.stdin.read()
    server = AppServer()
    try:
        server.request(
            "initialize",
            {
                "clientInfo": {
                    "name": "browser_hooks", "title": "Browser Hooks", "version": "1"
                }
            },
        )
        server.send({"method": "initialized", "params": {}})
        params = {"cwd": os.getcwd()}
        if len(sys.argv) == 2:
            params.update(threadId=sys.argv[1], excludeTurns=True)
            result = server.request("thread/resume", params)
        else:
            result = server.request("thread/start", params)
        thread = result["thread"]["id"]
        UUID(thread)
        if len(sys.argv) == 2 and thread != sys.argv[1]:
            raise HookError("session_invalid", "Codex")
        turn = server.request(
            "turn/start",
            {
                "threadId": thread,
                "cwd": os.getcwd(),
                "input": [{"type": "text", "text": prompt}],
            },
        )["turn"]["id"]
        answer = ""
        while True:
            event = server.events.popleft() if server.events else server.receive()
            params = event.get("params", {})
            if params.get("threadId") != thread:
                continue
            if event.get("method") == "item/completed" and params.get("turnId") == turn:
                item = params.get("item", {})
                if item.get("type") == "agentMessage" and item.get("phase") != "commentary":
                    answer = item.get("text", "")
            if event.get("method") == "turn/completed" and params["turn"]["id"] == turn:
                completed = params["turn"]
                if completed["status"] == "interrupted":
                    raise HookError("cancelled", "Codex")
                if completed["status"] != "completed":
                    raise classify(json.dumps(completed.get("error")), "Codex")
                break
        if not isinstance(answer, str) or not answer.strip():
            raise HookError("invalid_response", "Codex")
    finally:
        server.close()
    print(json.dumps({
        "session_id": thread, "answer": answer, "chat_url": f"codex://threads/{thread}"
    }))


if __name__ == "__main__":
    try:
        run()
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
        safe = error if isinstance(error, HookError) else HookError("invalid_response", "Codex")
        raise SystemExit(report(safe))
