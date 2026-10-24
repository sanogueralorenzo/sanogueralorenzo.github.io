#!/usr/bin/env python3
"""Run Crest's local compatibility corpus in isolated installed references."""

from __future__ import annotations

import argparse
import contextlib
import dataclasses
import datetime
import http.client
import json
import os
import pathlib
import plistlib
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from collections.abc import Iterator, Sequence
from typing import Any


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURE_DIRECTORY = REPOSITORY_ROOT / "CrestTestFixtures"
NETWORK_SERVER = FIXTURE_DIRECTORY / "network-server.py"


@dataclasses.dataclass(frozen=True)
class ApplicationMetadata:
    name: str
    version: str
    build: str
    executable: pathlib.Path


@dataclasses.dataclass(frozen=True)
class ClickWindowLease:
    accessibility_identifier: str

    def __post_init__(self) -> None:
        identifier = self.accessibility_identifier
        if (
            not identifier
            or len(identifier) > 512
            or any(ord(character) < 32 for character in identifier)
        ):
            raise ValueError("Click returned an invalid accessibility window identifier.")


@dataclasses.dataclass(frozen=True)
class CorpusResult:
    passed: int
    total: int
    failures: int
    duration_ms: float
    user_agent: str
    results: tuple[dict[str, Any], ...]

    @classmethod
    def from_payload(cls, payload: object) -> "CorpusResult":
        if not isinstance(payload, dict):
            raise ValueError("Corpus result must be an object.")
        passed = _required_integer(payload, "passed")
        total = _required_integer(payload, "total")
        failures = _required_integer(payload, "failures")
        duration_ms = payload.get("durationMs")
        user_agent = payload.get("userAgent")
        details = payload.get("results")
        if total <= 0 or passed < 0 or failures < 0 or passed + failures != total:
            raise ValueError("Corpus result summary is inconsistent.")
        if not isinstance(duration_ms, (int, float)) or isinstance(duration_ms, bool) or duration_ms < 0:
            raise ValueError("Corpus duration is invalid.")
        if not isinstance(user_agent, str) or not user_agent:
            raise ValueError("Corpus user agent is missing.")
        if not isinstance(details, list) or not all(isinstance(item, dict) for item in details):
            raise ValueError("Corpus result details are invalid.")
        return cls(
            passed=passed,
            total=total,
            failures=failures,
            duration_ms=float(duration_ms),
            user_agent=user_agent,
            results=tuple(item.copy() for item in details),
        )

    @property
    def succeeded(self) -> bool:
        return self.failures == 0

    def as_json(self) -> dict[str, object]:
        return {
            "passed": self.passed,
            "total": self.total,
            "failures": self.failures,
            "durationMs": round(self.duration_ms, 1),
            "userAgent": self.user_agent,
            "results": list(self.results),
        }


@dataclasses.dataclass(frozen=True)
class NetworkMetrics:
    total_requests: int
    total_response_bytes: int
    requests: dict[str, int]
    response_bytes: dict[str, int]

    @classmethod
    def from_payload(cls, payload: object) -> "NetworkMetrics":
        if not isinstance(payload, dict):
            raise ValueError("Network metrics must be an object.")
        if payload.get("server") != "crest-network-fixture-v1":
            raise ValueError("Network metrics came from an unknown fixture server.")
        total_requests = _required_nonnegative_integer(payload, "totalRequests", "Network")
        total_response_bytes = _required_nonnegative_integer(
            payload, "totalResponseBytes", "Network"
        )
        requests = _nonnegative_integer_map(payload.get("requests"), "request")
        response_bytes = _nonnegative_integer_map(payload.get("responseBytes"), "response-byte")
        if sum(requests.values()) != total_requests:
            raise ValueError("Network request total is inconsistent.")
        if sum(response_bytes.values()) != total_response_bytes:
            raise ValueError("Network response-byte total is inconsistent.")
        return cls(total_requests, total_response_bytes, requests, response_bytes)

    def as_json(self) -> dict[str, object]:
        return {
            "totalRequests": self.total_requests,
            "totalServedFileBytes": self.total_response_bytes,
            "requests": self.requests.copy(),
            "servedFileBytes": self.response_bytes.copy(),
        }


def _required_integer(payload: dict[object, object], key: str) -> int:
    value = payload.get(key)
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError(f"Corpus {key} is invalid.")
    return value


def _required_nonnegative_integer(
    payload: dict[object, object], key: str, subject: str
) -> int:
    value = payload.get(key)
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ValueError(f"{subject} {key} is invalid.")
    return value


def _nonnegative_integer_map(value: object, subject: str) -> dict[str, int]:
    if not isinstance(value, dict):
        raise ValueError(f"Network {subject} map is invalid.")
    if not all(
        isinstance(key, str)
        and isinstance(count, int)
        and not isinstance(count, bool)
        and count >= 0
        for key, count in value.items()
    ):
        raise ValueError(f"Network {subject} map is invalid.")
    return dict(value)


def read_application_metadata(application: pathlib.Path) -> ApplicationMetadata:
    application = application.resolve()
    info_path = application / "Contents" / "Info.plist"
    if not info_path.is_file():
        raise ValueError(f"Application metadata is missing: {info_path}")
    with info_path.open("rb") as info_file:
        info = plistlib.load(info_file)
    executable_name = info.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or not executable_name:
        raise ValueError(f"Application executable is missing from {info_path}")
    executable = application / "Contents" / "MacOS" / executable_name
    if not executable.is_file():
        raise ValueError(f"Application executable does not exist: {executable}")
    return ApplicationMetadata(
        name=str(info.get("CFBundleDisplayName") or info.get("CFBundleName") or application.stem),
        version=str(info.get("CFBundleShortVersionString") or "unknown"),
        build=str(info.get("CFBundleVersion") or "unknown"),
        executable=executable,
    )


def exact_application_process_is_present(
    executable: pathlib.Path, process_commands: Sequence[str]
) -> bool:
    expected = str(executable)
    return any(command.strip() == expected for command in process_commands)


def _application_is_running(executable: pathlib.Path) -> bool:
    result = subprocess.run(
        ["ps", "-axo", "command="],
        text=True,
        capture_output=True,
        check=True,
    )
    return exact_application_process_is_present(executable, result.stdout.splitlines())


def arc_launch_command(
    *,
    executable: pathlib.Path,
    profile: pathlib.Path,
    task_root: pathlib.Path,
    url: str,
) -> list[str]:
    resolved_root = task_root.resolve()
    resolved_profile = profile.resolve()
    if not resolved_profile.is_relative_to(resolved_root) or resolved_profile == resolved_root:
        raise ValueError(f"Arc profile is outside the task root: {resolved_profile}")
    return [
        str(executable),
        f"--user-data-dir={resolved_profile}",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-sync",
        "--disable-background-networking",
        url,
    ]


@dataclasses.dataclass(frozen=True)
class BrowserResult:
    application: ApplicationMetadata
    isolation: str
    corpus: CorpusResult
    network: NetworkMetrics

    def as_json(self) -> dict[str, object]:
        return {
            "browser": self.application.name,
            "version": self.application.version,
            "build": self.application.build,
            "isolation": self.isolation,
            "corpus": self.corpus.as_json(),
            "network": self.network.as_json(),
        }


class FixtureServer:
    def __init__(self, task_root: pathlib.Path) -> None:
        self._task_root = task_root
        self._process: subprocess.Popen[bytes] | None = None
        self.port = _available_loopback_port()

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def start(self) -> None:
        self._process = subprocess.Popen(
            [
                sys.executable,
                str(NETWORK_SERVER),
                "--port",
                str(self.port),
                "--directory",
                str(FIXTURE_DIRECTORY),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if self._process.poll() is not None:
                raise RuntimeError("The local compatibility server exited during startup.")
            try:
                with urllib.request.urlopen(
                    f"{self.base_url}/__crest_network_metrics__", timeout=0.5
                ):
                    return
            except (urllib.error.URLError, TimeoutError):
                time.sleep(0.05)
        raise TimeoutError("The local compatibility server did not become ready.")

    def stop(self) -> None:
        process = self._process
        self._process = None
        if process is None or process.poll() is not None:
            return
        try:
            urllib.request.urlopen(f"{self.base_url}/__crest_network_stop__", timeout=1).close()
            process.wait(timeout=3)
        except (OSError, subprocess.TimeoutExpired, urllib.error.URLError):
            _terminate_process_group(process)

    def reset_network_metrics(self) -> None:
        request = urllib.request.Request(
            f"{self.base_url}/__crest_network_reset__",
            method="GET",
        )
        with urllib.request.urlopen(request, timeout=1) as response:
            if response.status != http.client.NO_CONTENT:
                raise RuntimeError("The local compatibility server did not reset its metrics.")

    def network_metrics(self) -> NetworkMetrics:
        with urllib.request.urlopen(
            f"{self.base_url}/__crest_network_metrics__", timeout=1
        ) as response:
            return NetworkMetrics.from_payload(json.load(response))


def _available_loopback_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def _terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)
        return
    except (ProcessLookupError, subprocess.TimeoutExpired):
        pass
    with contextlib.suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGKILL)
    with contextlib.suppress(subprocess.TimeoutExpired):
        process.wait(timeout=2)


def wait_for_corpus_result(
    *,
    server: FixtureServer,
    run_id: str,
    timeout: float,
    browser_process: subprocess.Popen[bytes] | None = None,
) -> CorpusResult:
    result_url = f"{server.base_url}/__crest_corpus_result__?{urllib.parse.urlencode({'run': run_id})}"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if browser_process is not None and browser_process.poll() is not None:
            raise RuntimeError("The reference browser exited before reporting its result.")
        try:
            with urllib.request.urlopen(result_url, timeout=1) as response:
                return CorpusResult.from_payload(json.load(response))
        except urllib.error.HTTPError as error:
            if error.code != http.client.NOT_FOUND:
                raise
        except (TimeoutError, urllib.error.URLError):
            pass
        time.sleep(0.1)
    raise TimeoutError(f"The corpus did not report within {timeout:.0f} seconds.")


def run_arc(
    *,
    application: pathlib.Path,
    task_root: pathlib.Path,
    server: FixtureServer,
    timeout: float,
) -> BrowserResult:
    metadata = read_application_metadata(application)
    if _application_is_running(metadata.executable):
        raise RuntimeError(
            "Arc is already running. Its single-instance router will not open a task-owned clean "
            "profile; quit Arc normally before this controlled comparison rather than allowing "
            "the runner to disturb the active session."
        )
    server.reset_network_metrics()
    run_id = f"arc-{uuid.uuid4()}"
    corpus_url = f"{server.base_url}/compatibility.html?{urllib.parse.urlencode({'crestRun': run_id})}"
    profile = task_root / "Arc-clean-profile"
    command = arc_launch_command(
        executable=metadata.executable,
        profile=profile,
        task_root=task_root,
        url=corpus_url,
    )
    process = subprocess.Popen(
        command,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        corpus = wait_for_corpus_result(
            server=server,
            run_id=run_id,
            timeout=timeout,
            browser_process=process,
        )
        network = server.network_metrics()
    finally:
        _terminate_process_group(process)
    return BrowserResult(metadata, "task-owned clean Chromium profile", corpus, network)


def _wait_for_click(executable: pathlib.Path, timeout: float = 8) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if _application_is_running(executable):
            return
        time.sleep(0.1)
    raise TimeoutError("Click did not launch.")


def _run_apple_script(script: str, *, environment: dict[str, str] | None = None) -> str:
    try:
        result = subprocess.run(
            ["osascript", "-"],
            input=script,
            text=True,
            capture_output=True,
            env=environment,
            timeout=20,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(
            "Click automation timed out before completing its bounded window transaction."
        ) from error
    if result.returncode != 0:
        raise RuntimeError(f"Click automation failed: {result.stderr.strip()}")
    return result.stdout.strip()


def click_incognito_navigation_script() -> str:
    return """
        set targetURL to system attribute "CREST_REFERENCE_URL"
        tell application "System Events"
          tell process "Click"
            set frontmost to true
            set priorWindowCount to count windows
            set priorWindowIdentifiers to {}
            set taskWindow to missing value
            repeat with existingWindow in windows
              try
                set end of priorWindowIdentifiers to value of attribute "AXIdentifier" of existingWindow
              end try
            end repeat

            try
              click menu item "New Incognito Window" of menu 1 of menu bar item "File" of menu bar 1
              repeat 80 times
                if (count windows) > priorWindowCount then exit repeat
                delay 0.1
              end repeat
              if (count windows) is not greater than priorWindowCount then
                error "Click did not create an Incognito window."
              end if

              repeat with candidateWindow in windows
                try
                  set candidateIdentifier to value of attribute "AXIdentifier" of candidateWindow
                  if priorWindowIdentifiers does not contain candidateIdentifier then
                    set taskWindow to candidateWindow
                    exit repeat
                  end if
                end try
              end repeat
              if taskWindow is missing value then
                error "Click did not expose a unique Incognito window identifier."
              end if

              perform action "AXRaise" of taskWindow
              keystroke "l" using command down
              repeat 30 times
                if exists text field 1 of group 1 of taskWindow then exit repeat
                delay 0.1
              end repeat
              if not (exists text field 1 of group 1 of taskWindow) then
                error "Click did not expose its address field."
              end if
              set value of text field 1 of group 1 of taskWindow to targetURL
              delay 0.2
              key code 36
              return value of attribute "AXIdentifier" of taskWindow
            on error errorMessage number errorNumber
              if taskWindow is not missing value then
                try
                  perform action "AXRaise" of taskWindow
                  click menu item "Close Window" of menu 1 of menu bar item "File" of menu bar 1
                end try
              end if
              error errorMessage number errorNumber
            end try
          end tell
        end tell
        """


def click_window_cleanup_script() -> str:
    return """
        set targetIdentifier to system attribute "CREST_CLICK_WINDOW_IDENTIFIER"
        tell application "System Events"
          tell process "Click"
            set matchingWindows to every window whose value of attribute "AXIdentifier" is targetIdentifier
            if (count matchingWindows) is greater than 1 then
              error "Click exposed duplicate task-window identifiers."
            end if
            if (count matchingWindows) is 1 then
              set targetWindow to item 1 of matchingWindows
              perform action "AXRaise" of targetWindow
              click menu item "Close Window" of menu 1 of menu bar item "File" of menu bar 1
            end if
          end tell
        end tell
        """


def _open_click_incognito(corpus_url: str) -> ClickWindowLease:
    environment = os.environ.copy()
    environment["CREST_REFERENCE_URL"] = corpus_url
    identifier = _run_apple_script(
        click_incognito_navigation_script(),
        environment=environment,
    )
    return ClickWindowLease(identifier)


def _close_click_incognito(lease: ClickWindowLease) -> None:
    environment = os.environ.copy()
    environment["CREST_CLICK_WINDOW_IDENTIFIER"] = lease.accessibility_identifier
    _run_apple_script(
        click_window_cleanup_script(),
        environment=environment,
    )


def _quit_click() -> None:
    _run_apple_script(
        """
        tell application "System Events"
          tell process "Click"
            click menu item "Quit Click" of menu 1 of menu bar item "Click" of menu bar 1
          end tell
        end tell
        """
    )


def run_click(
    *,
    application: pathlib.Path,
    server: FixtureServer,
    timeout: float,
    reuse_running_session: bool = False,
) -> BrowserResult:
    metadata = read_application_metadata(application)
    session_was_running = _application_is_running(metadata.executable)
    if session_was_running and not reuse_running_session:
        raise RuntimeError(
            "Click is already running. Quit Click normally before this controlled comparison "
            "or explicitly allow one exact task-owned Incognito window."
        )
    owned_process = None
    if not session_was_running:
        owned_process = subprocess.Popen(
            [str(metadata.executable)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    window_lease: ClickWindowLease | None = None
    try:
        _wait_for_click(metadata.executable)
        server.reset_network_metrics()
        run_id = f"click-{uuid.uuid4()}"
        corpus_url = f"{server.base_url}/compatibility.html?{urllib.parse.urlencode({'crestRun': run_id})}"
        window_lease = _open_click_incognito(corpus_url)
        corpus = wait_for_corpus_result(server=server, run_id=run_id, timeout=timeout)
        network = server.network_metrics()
    finally:
        if window_lease is not None:
            if session_was_running:
                _close_click_incognito(window_lease)
            else:
                with contextlib.suppress(RuntimeError):
                    _close_click_incognito(window_lease)
        if owned_process is not None:
            with contextlib.suppress(RuntimeError, subprocess.TimeoutExpired):
                _quit_click()
                owned_process.wait(timeout=3)
            _terminate_process_group(owned_process)
    isolation = "native nonpersistent Incognito window"
    if session_was_running:
        isolation += " in preserved running Click session"
    return BrowserResult(metadata, isolation, corpus, network)


def _selected_browsers(value: str) -> Sequence[str]:
    if value == "all":
        return ("arc", "click")
    return (value,)


def parse_arguments(arguments: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser", choices=("all", "arc", "click"), default="all")
    parser.add_argument("--arc-app", type=pathlib.Path, default=pathlib.Path("/Applications/Arc.app"))
    parser.add_argument(
        "--click-app", type=pathlib.Path, default=pathlib.Path("/Applications/Click.app")
    )
    parser.add_argument(
        "--reuse-running-click",
        action="store_true",
        help="Open and close one exact Incognito window without quitting a running Click session.",
    )
    parser.add_argument("--timeout", type=float, default=45)
    parser.add_argument("--output", type=pathlib.Path)
    return parser.parse_args(arguments)


def run(arguments: argparse.Namespace) -> dict[str, object]:
    if arguments.timeout <= 0:
        raise ValueError("Timeout must be positive.")
    with tempfile.TemporaryDirectory(
        prefix="crest-reference-corpus-", dir="/private/tmp"
    ) as temporary_directory:
        task_root = pathlib.Path(temporary_directory)
        server = FixtureServer(task_root)
        server.start()
        try:
            results: list[BrowserResult] = []
            for browser in _selected_browsers(arguments.browser):
                if browser == "arc":
                    result = run_arc(
                        application=arguments.arc_app,
                        task_root=task_root,
                        server=server,
                        timeout=arguments.timeout,
                    )
                else:
                    result = run_click(
                        application=arguments.click_app,
                        server=server,
                        timeout=arguments.timeout,
                        reuse_running_session=arguments.reuse_running_click,
                    )
                results.append(result)
        finally:
            server.stop()
    return {
        "generatedAt": datetime.datetime.now(datetime.UTC).isoformat(),
        "fixture": "CrestTestFixtures/compatibility.html",
        "results": [result.as_json() for result in results],
    }


def main(arguments: Sequence[str] | None = None) -> int:
    parsed_arguments = parse_arguments(arguments if arguments is not None else sys.argv[1:])
    try:
        report = run(parsed_arguments)
    except (OSError, RuntimeError, TimeoutError, ValueError, urllib.error.URLError) as error:
        print(f"Reference corpus failed: {error}", file=sys.stderr)
        return 1
    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if parsed_arguments.output is None:
        sys.stdout.write(rendered)
    else:
        parsed_arguments.output.write_text(rendered, encoding="utf-8")
    return 0 if all(item["corpus"]["failures"] == 0 for item in report["results"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
