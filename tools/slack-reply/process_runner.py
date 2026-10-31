"""Own CLI subprocesses and clean up their process groups."""

import os
import signal
import subprocess
import time
from threading import Lock


def signal_group(process, sig):
    try:
        os.killpg(process.pid, sig)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        if sig == 0:
            return True
        raise


def stop_processes(processes):
    for process in processes:
        signal_group(process, signal.SIGTERM)
    deadline = time.monotonic() + 2
    for process in processes:
        process.poll()
        while signal_group(process, 0) and time.monotonic() < deadline:
            time.sleep(0.02)
            process.poll()
    for process in processes:
        signal_group(process, signal.SIGKILL)
        process.wait()


class ProcessRunner:
    def __init__(self):
        self.lock = Lock()
        self.active = set()
        self.closed = False

    def run(self, command, prompt, workspace, env):
        with self.lock:
            if self.closed:
                raise RuntimeError("Slack Reply is shutting down")
            process = subprocess.Popen(
                command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, cwd=workspace, env=env, start_new_session=True,
            )
            self.active.add(process)
        try:
            with process:
                try:
                    while True:
                        try:
                            stdout, stderr = process.communicate(prompt, timeout=0.2)
                            return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
                        except subprocess.TimeoutExpired:
                            prompt = None
                            # A child can inherit the pipes after its CLI parent exits.
                            if process.poll() is not None:
                                stop_processes((process,))
                finally:
                    stop_processes((process,))
        finally:
            with self.lock:
                self.active.discard(process)

    def close(self):
        with self.lock:
            self.closed = True
            active = tuple(self.active)
        stop_processes(active)


processes = ProcessRunner()
