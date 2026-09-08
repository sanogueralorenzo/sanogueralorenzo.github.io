"""A disposable, tool-free Pi session for meeting notes."""
import json
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import tempfile
import time
import uuid

PROVIDERS = {"openai": ("openai-codex", "gpt-5.6-luna"),
             "anthropic": ("anthropic", "claude-haiku-4-5-20251001")}
ISOLATION = ["--offline", "--no-session", "--no-tools", "--no-extensions", "--no-skills",
             "--no-prompt-templates", "--no-context-files", "--no-themes", "--no-approve"]
ACTIVE_PROCESS = None
ACTIVE_DIRECTORY = None
FAILURE = "Pi did not return a complete note. Check your Pi sign-in, then Retry."


def stop_active():
    if ACTIVE_PROCESS is not None:
        try:
            os.killpg(ACTIVE_PROCESS.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if ACTIVE_DIRECTORY:
        shutil.rmtree(ACTIVE_DIRECTORY, ignore_errors=True)


def environment():
    env = {key: os.environ[key] for key in ("HOME", "PATH", "USER", "TMPDIR", "SSL_CERT_FILE", "SSL_CERT_DIR") if key in os.environ}
    return dict(env, LANG="en_US.UTF-8", TERM="dumb", NO_COLOR="1", PI_OFFLINE="1", PI_TELEMETRY="0")


def run_command(args, env, root, timeout):
    global ACTIVE_PROCESS
    process = subprocess.Popen(args, cwd=root, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, start_new_session=True)
    ACTIVE_PROCESS = process
    try:
        output = process.communicate(timeout=timeout)[0]
        return process.returncode, output
    finally:
        if process.poll() is None:
            stop_active()
            process.wait()
        process.stdout.close()
        ACTIVE_PROCESS = None


class PiProcessor:
    def __init__(self, provider, brief):
        if provider not in PROVIDERS:
            raise ValueError("Choose OpenAI or Anthropic in Provider before sending this transcript to Pi.")
        self.provider, self.model = PROVIDERS[provider]
        self.brief = brief
        self.process = None
        self.directory = None
        self.buffer = b""

    def __enter__(self):
        try:
            self.start()
            return self
        except BaseException:
            self.close()
            raise

    def __exit__(self, *args):
        self.close()

    def start(self):
        global ACTIVE_PROCESS, ACTIVE_DIRECTORY
        executable = shutil.which("pi")
        if not executable:
            raise ValueError("Install Pi, open pi in Terminal and use /login, then Retry.")
        self.directory = tempfile.TemporaryDirectory(prefix="minutes-pi-")
        root = Path(self.directory.name)
        ACTIVE_DIRECTORY = str(root)
        env = environment()
        auth_env = dict(env)
        if "PI_CODING_AGENT_DIR" in os.environ:
            auth_env["PI_CODING_AGENT_DIR"] = os.environ["PI_CODING_AGENT_DIR"]
        isolated_env = dict(env, PI_CODING_AGENT_DIR=str(root))
        try:
            status, help_text = run_command([executable, *ISOLATION, "--help"], isolated_env, root, 10)
            required = ISOLATION + ["--mode", "--system-prompt", "--thinking", "--extension"]
            if status or any(flag.encode() not in help_text for flag in required):
                raise ValueError()
        except (ValueError, subprocess.TimeoutExpired):
            raise ValueError("Update Pi: this version lacks the isolation options Minutes requires.") from None
        try:
            status, raw = run_command([executable, "auth", "check", "--provider", self.provider, "--json", "--credentials"], auth_env, root, 20)
            value = json.loads(raw)
            credential = value.get("credentials", "")
            if status or value.get("status") != "ready" or not isinstance(credential, str) or not credential or credential.startswith("!") or "\n" in credential:
                raise ValueError()
        except (ValueError, AttributeError, subprocess.TimeoutExpired):
            raise ValueError(f"Sign in to {self.provider} in Pi: open pi in Terminal, use /login, then Retry.") from None
        snapshot = ({"type": "oauth", "access": credential, "refresh": "", "expires": (time.time() + 600) * 1000}
                    if value.get("authType") == "oauth" else {"type": "api_key", "key": credential})
        auth_path = root / "auth.json"
        auth_path.touch(mode=0o600)
        auth_path.write_text(json.dumps({self.provider: snapshot}))
        (root / "settings.json").write_text('{"compaction":{"enabled":false},"retry":{"enabled":false}}')
        env["PI_CODING_AGENT_DIR"] = str(root)
        args = [executable, *ISOLATION, "--mode", "rpc", "--provider", self.provider, "--model", self.model,
                "--thinking", "off", "--system-prompt", self.brief]
        if self.provider == "openai-codex":
            extension = root / "request.mjs"
            extension.write_text('export default function(pi) { pi.on("before_provider_request", event => ({...event.payload, service_tier:"priority", reasoning:{effort:"none"}})); }')
            args += ["--extension", str(extension)]
        self.process = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                        cwd=root, env=env, start_new_session=True)
        ACTIVE_PROCESS = self.process
        os.set_blocking(self.process.stdin.fileno(), False)
        self.started = time.monotonic()
        self.reset()

    def close(self):
        global ACTIVE_PROCESS, ACTIVE_DIRECTORY
        if self.process is not None:
            process = self.process
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=1)
                except (ProcessLookupError, subprocess.TimeoutExpired):
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait()
            process.stdin.close()
            process.stdout.close()
            if ACTIVE_PROCESS is process:
                ACTIVE_PROCESS = None
            self.process = None
        if self.directory is not None:
            self.directory.cleanup()
            self.directory = None
            ACTIVE_DIRECTORY = None
        self.buffer = b""

    def event(self, deadline):
        while b"\n" not in self.buffer:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.process.stdout], [], [], remaining)[0]:
                raise TimeoutError("Pi took too long. Your saved transcript is available; Retry.")
            data = os.read(self.process.stdout.fileno(), 65536)
            if not data:
                raise RuntimeError(FAILURE)
            self.buffer += data
            if len(self.buffer) > 8 * 1024 * 1024:
                raise RuntimeError(FAILURE)
        line, self.buffer = self.buffer.split(b"\n", 1)
        try:
            event = json.loads(line)
            if not isinstance(event, dict):
                raise ValueError()
            return event
        except ValueError:
            raise RuntimeError(FAILURE) from None

    def send(self, command, **fields):
        identifier = str(uuid.uuid4())
        data = json.dumps(dict(id=identifier, type=command, **fields)).encode() + b"\n"
        deadline = time.monotonic() + (900 if command == "prompt" else 15)
        offset = 0
        while offset < len(data):
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([], [self.process.stdin], [], remaining)[1]:
                raise TimeoutError("Pi took too long. Retry the saved meeting.")
            offset += os.write(self.process.stdin.fileno(), data[offset:offset + 65536])
        response = None
        output = None
        ended = False
        while response is None or (command == "prompt" and not ended):
            event = self.event(deadline)
            kind = event.get("type", "")
            if kind == "response" and event.get("id") == identifier:
                if not event.get("success"):
                    raise RuntimeError(FAILURE)
                response = event
            if kind.startswith("tool_execution") or kind == "error":
                raise RuntimeError(FAILURE)
            if command == "prompt" and kind == "message_end" and event.get("message", {}).get("role") == "assistant":
                message = event["message"]
                content = message.get("content", [])
                if output is not None or message.get("stopReason") != "stop" or not content or any(item.get("type") not in ("text", "thinking") for item in content):
                    raise RuntimeError(FAILURE)
                output = "".join(item["text"] for item in content if item["type"] == "text")
            if command == "prompt" and kind == "agent_end":
                if not output:
                    raise RuntimeError(FAILURE)
                ended = True
        return output if command == "prompt" else response.get("data", {})

    def reset(self):
        self.send("new_session")
        state = self.send("get_state")
        if state.get("messageCount") != 0 or state.get("pendingMessageCount") != 0 or state.get("isStreaming"):
            raise RuntimeError(FAILURE)
        model = state.get("model", {})
        if model.get("id") != self.model or model.get("provider") != self.provider:
            raise RuntimeError("Update Pi: the selected Minutes model is unavailable.")
        self.model_info = model

    @property
    def input_budget(self):
        # One UTF-8 byte per token is deliberately conservative. Reserve the catalog's
        # full output allowance plus framing/headroom; never rely on English averages.
        window = self.model_info.get("contextWindow")
        output = self.model_info.get("maxTokens")
        if type(window) is not int or type(output) is not int or output <= 0:
            raise ValueError("Update Pi: model input limits are unavailable.")
        budget = window - output - len(self.brief.encode()) - 8192
        if budget < 4096:
            raise ValueError("Pi reports too little input capacity for meeting notes.")
        return budget

    def generate(self, source):
        try:
            if self.process is None:
                raise RuntimeError(FAILURE)
            # Startup and each successful request leave a verified empty session.
            # Renew the access-only snapshot before another request in a long job.
            if time.monotonic() - self.started > 180:
                self.close()
                self.start()
            if len(source.encode()) > self.input_budget:
                raise ValueError("This excerpt exceeds Pi's input budget. Retry to split the saved transcript.")
            result = self.send("prompt", message=source)
            self.reset()
            return result
        except BaseException:
            self.close()
            raise
