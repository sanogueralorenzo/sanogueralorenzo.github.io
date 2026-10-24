#!/usr/bin/env python3
"""Serve Crest's performance corpus with exact request and byte counters."""

from __future__ import annotations

import argparse
import collections
import functools
import http.server
import json
import os
import pathlib
import re
import ssl
import tempfile
import threading
import time
from typing import BinaryIO
import urllib.parse


CORPUS_RESULT_LIMIT = 64 * 1024
CORPUS_RUN_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,128}$")


class NetworkFixtureState:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.reset()

    def reset(self) -> None:
        with self._lock:
            self._requests: collections.Counter[str] = collections.Counter()
            self._response_bytes: collections.Counter[str] = collections.Counter()
            self._corpus_results: dict[str, dict[str, object]] = {}
            self._reset_at = time.time()

    def record_request(self, target: str) -> None:
        with self._lock:
            self._requests[target] += 1

    def record_response_bytes(self, target: str, byte_count: int) -> None:
        with self._lock:
            self._response_bytes[target] += byte_count

    def record_corpus_result(self, run_id: str, result: dict[str, object]) -> None:
        with self._lock:
            self._corpus_results[run_id] = result.copy()

    def corpus_result(self, run_id: str) -> dict[str, object] | None:
        with self._lock:
            result = self._corpus_results.get(run_id)
            return result.copy() if result is not None else None

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            return {
                "server": "crest-network-fixture-v1",
                "resetAt": self._reset_at,
                "totalRequests": sum(self._requests.values()),
                "totalResponseBytes": sum(self._response_bytes.values()),
                "requests": dict(sorted(self._requests.items())),
                "responseBytes": dict(sorted(self._response_bytes.items())),
            }


def write_metrics_snapshot(output: pathlib.Path, state: NetworkFixtureState) -> None:
    output = output.resolve()
    temporary_path: pathlib.Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=output.parent,
            prefix=f".{output.name}.",
            suffix=".tmp",
            delete=False,
        ) as temporary_file:
            temporary_path = pathlib.Path(temporary_file.name)
            json.dump(state.snapshot(), temporary_file, indent=2, sort_keys=True)
            temporary_file.write("\n")
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        temporary_path.replace(output)
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink()


class NetworkFixtureHandler(http.server.SimpleHTTPRequestHandler):
    state: NetworkFixtureState

    def do_GET(self) -> None:  # noqa: N802 - inherited HTTP handler name
        request = urllib.parse.urlsplit(self.path)
        if request.path == "/__crest_network_metrics__":
            self._send_json(self.state.snapshot())
            return
        if request.path == "/__crest_network_reset__":
            self.state.reset()
            self.send_response(204)
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            return
        if request.path == "/__crest_network_stop__":
            self.send_response(204)
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            return
        if request.path == "/__crest_corpus_result__":
            run_id = self._corpus_run_id(request.query)
            if run_id is None:
                self._send_json({"error": "invalid run"}, status=400)
                return
            result = self.state.corpus_result(run_id)
            if result is None:
                self._send_json({"status": "pending"}, status=404)
                return
            self._send_json(result)
            return

        self._current_metric_target = self.path
        self.state.record_request(self.path)
        try:
            super().do_GET()
        finally:
            self._current_metric_target = None

    def do_POST(self) -> None:  # noqa: N802 - inherited HTTP handler name
        request = urllib.parse.urlsplit(self.path)
        if request.path != "/__crest_corpus_result__":
            self._send_json({"error": "not found"}, status=404)
            return

        run_id = self._corpus_run_id(request.query)
        if run_id is None:
            self._send_json({"error": "invalid run"}, status=400)
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send_json({"error": "invalid content length"}, status=400)
            return
        if content_length < 2 or content_length > CORPUS_RESULT_LIMIT:
            self._send_json({"error": "result too large"}, status=413)
            return
        try:
            value = json.loads(self.rfile.read(content_length))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._send_json({"error": "invalid JSON"}, status=400)
            return
        if not isinstance(value, dict):
            self._send_json({"error": "result must be an object"}, status=400)
            return

        self.state.record_corpus_result(run_id, value)
        self.send_response(204)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def copyfile(self, source: BinaryIO, outputfile: BinaryIO) -> None:
        byte_count = 0
        while chunk := source.read(64 * 1024):
            outputfile.write(chunk)
            byte_count += len(chunk)
        if target := getattr(self, "_current_metric_target", None):
            self.state.record_response_bytes(target, byte_count)

    def log_message(self, format: str, *arguments: object) -> None:
        return

    def _corpus_run_id(self, query: str) -> str | None:
        values = urllib.parse.parse_qs(query, keep_blank_values=True).get("run", [])
        if len(values) != 1 or CORPUS_RUN_PATTERN.fullmatch(values[0]) is None:
            return None
        return values[0]

    def _send_json(self, value: dict[str, object], status: int = 200) -> None:
        data = json.dumps(value, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)


def create_server(
    *,
    host: str,
    port: int,
    directory: pathlib.Path,
) -> http.server.ThreadingHTTPServer:
    state = NetworkFixtureState()
    NetworkFixtureHandler.state = state
    handler = functools.partial(
        NetworkFixtureHandler,
        directory=str(directory.resolve()),
    )
    server = http.server.ThreadingHTTPServer((host, port), handler)
    server.daemon_threads = True
    return server


def configure_tls(
    server: http.server.ThreadingHTTPServer,
    *,
    certificate: pathlib.Path,
    private_key: pathlib.Path,
) -> None:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(
        certfile=str(certificate.resolve()),
        keyfile=str(private_key.resolve()),
    )
    server.socket = context.wrap_socket(server.socket, server_side=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument(
        "--directory",
        type=pathlib.Path,
        default=pathlib.Path(__file__).parent,
    )
    parser.add_argument("--metrics-output", type=pathlib.Path)
    parser.add_argument("--tls-cert", type=pathlib.Path)
    parser.add_argument("--tls-key", type=pathlib.Path)
    arguments = parser.parse_args()
    if (arguments.tls_cert is None) != (arguments.tls_key is None):
        parser.error("--tls-cert and --tls-key must be provided together")
    server = create_server(
        host=arguments.host,
        port=arguments.port,
        directory=arguments.directory,
    )
    if arguments.tls_cert is not None and arguments.tls_key is not None:
        configure_tls(
            server,
            certificate=arguments.tls_cert,
            private_key=arguments.tls_key,
        )
    try:
        server.serve_forever()
    finally:
        server.server_close()
        if arguments.metrics_output is not None:
            write_metrics_snapshot(arguments.metrics_output, NetworkFixtureHandler.state)


if __name__ == "__main__":
    main()
