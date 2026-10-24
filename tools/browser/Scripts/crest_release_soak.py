#!/usr/bin/env python3
"""Run an isolated signed-Release memory soak for Crest's retained WebKit pages."""

from __future__ import annotations

import dataclasses
import datetime
import json
import os
import pathlib
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from collections.abc import Sequence
from typing import Any

from reference_browser_corpus import FixtureServer


PERFORMANCE_BUNDLE_ID = "com.pauldavis.crest.performance-soak"
PERFORMANCE_PRODUCT_NAME = "Crest Performance Soak"
WEBKIT_PROCESS_MARKERS = (
    "/com.apple.WebKit.GPU.xpc/",
    "/com.apple.WebKit.Networking.xpc/",
    "/com.apple.WebKit.WebContent.xpc/",
)
GPU_TRACE_SCHEMAS = (
    "metal-perf-overview-process-metric",
    "metal-perf-overview-gpu-state-metric",
    "metal-perf-overview-gpu-power-ctrl-state-metric",
    "metal-perf-overview-power-system-metric",
    "metal-perf-overview-layer-per-frame-metric",
)


@dataclasses.dataclass(frozen=True)
class FootprintMeasurement:
    current_bytes: int
    peak_bytes: int


@dataclasses.dataclass(frozen=True)
class GPUTraceMetricSeries:
    name: str
    values: tuple[float, ...]

    def as_json(self) -> dict[str, object]:
        return {
            "name": self.name,
            "sampleCount": len(self.values),
            "minimum": min(self.values),
            "maximum": max(self.values),
            "mean": sum(self.values) / len(self.values),
        }


@dataclasses.dataclass(frozen=True)
class GPUTraceTable:
    schema: str
    row_count: int
    series: tuple[GPUTraceMetricSeries, ...]

    def as_json(self) -> dict[str, object]:
        return {
            "schema": self.schema,
            "rowCount": self.row_count,
            "series": [item.as_json() for item in self.series],
        }


@dataclasses.dataclass(frozen=True)
class GPUTraceReport:
    process_id: int
    duration_seconds: float
    trace_bytes: int
    tables: tuple[GPUTraceTable, ...]

    def as_json(self) -> dict[str, object]:
        return {
            "template": "Game Performance Overview",
            "targetRole": "task-owned WebKit GPU XPC",
            "targetProcessIdentifier": self.process_id,
            "durationSeconds": self.duration_seconds,
            "traceBytes": self.trace_bytes,
            "tables": [table.as_json() for table in self.tables],
        }


@dataclasses.dataclass(frozen=True)
class ProcessFootprint:
    pid: int
    role: str
    current_bytes: int
    peak_bytes: int

    def as_json(self) -> dict[str, object]:
        return dataclasses.asdict(self)


@dataclasses.dataclass(frozen=True)
class ReleaseSoakSample:
    elapsed_seconds: float
    phase: str
    processes: tuple[ProcessFootprint, ...]

    @property
    def aggregate_bytes(self) -> int:
        return sum(process.current_bytes for process in self.processes)

    def as_json(self) -> dict[str, object]:
        return {
            "elapsedSeconds": round(self.elapsed_seconds, 3),
            "phase": self.phase,
            "aggregateBytes": self.aggregate_bytes,
            "processes": [process.as_json() for process in self.processes],
        }


def validate_owned_path(task_root: pathlib.Path, candidate: pathlib.Path) -> pathlib.Path:
    resolved_root = task_root.resolve()
    resolved_candidate = candidate.resolve()
    if resolved_candidate == resolved_root:
        raise ValueError(f"Generated path cannot be the task root itself: {resolved_candidate}")
    if not resolved_candidate.is_relative_to(resolved_root):
        raise ValueError(f"Generated path is outside the task root: {resolved_candidate}")
    return resolved_candidate


def gpu_trace_command(
    *,
    task_root: pathlib.Path,
    trace: pathlib.Path,
    gpu_process_id: int,
    duration: float,
) -> list[str]:
    owned_trace = validate_owned_path(task_root, trace)
    if gpu_process_id <= 0:
        raise ValueError("The WebKit GPU process identifier must be positive.")
    if duration <= 0:
        raise ValueError("The GPU trace duration must be positive.")
    rendered_duration = f"{duration:g}s"
    return [
        "xcrun",
        "xctrace",
        "record",
        "--template",
        "Game Performance Overview",
        "--attach",
        str(gpu_process_id),
        "--time-limit",
        rendered_duration,
        "--output",
        str(owned_trace),
        "--no-prompt",
        "--quiet",
    ]


def gpu_trace_export_command(
    *,
    task_root: pathlib.Path,
    trace: pathlib.Path,
    output: pathlib.Path,
    schema: str,
) -> list[str]:
    owned_trace = validate_owned_path(task_root, trace)
    owned_output = validate_owned_path(task_root, output)
    if schema not in GPU_TRACE_SCHEMAS:
        raise ValueError(f"The GPU trace schema is unsupported: {schema}")
    xpath = f"/trace-toc/run[@number='1']/data/table[@schema='{schema}']"
    return [
        "xcrun",
        "xctrace",
        "export",
        str(owned_trace),
        "--xpath",
        xpath,
        "--output",
        str(owned_output),
    ]


def select_owned_gpu_process_id(processes: dict[int, str]) -> int:
    process_ids = sorted(pid for pid, role in processes.items() if role == "gpu")
    if not process_ids:
        raise RuntimeError("Crest has no task-owned WebKit GPU process to trace.")
    if len(process_ids) > 1:
        raise RuntimeError("Crest has multiple task-owned WebKit GPU processes.")
    return process_ids[0]


def _formatted_xml_value(element: ET.Element) -> str:
    return element.attrib.get("fmt") or (element.text or "").strip()


def _metric_value(row: ET.Element) -> float | None:
    element = next((item for item in row if item.tag.endswith("fixed-decimal")), None)
    if element is None:
        return None
    match = re.search(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?", _formatted_xml_value(element))
    return float(match.group(0)) if match is not None else None


def _metric_name(row: ET.Element) -> str | None:
    element = next((item for item in row if "metric-name" in item.tag), None)
    if element is None:
        return None
    value = _formatted_xml_value(element)
    return value or None


def parse_gpu_metric_table(xml: str, *, schema: str) -> GPUTraceTable:
    root = ET.fromstring(xml)
    schema_names = {item.attrib.get("name") for item in root.iter("schema")}
    if schema not in schema_names:
        raise ValueError(f"GPU trace export does not contain the {schema} schema.")
    rows = list(root.iter("row"))
    grouped: dict[str, list[float]] = {}
    for row in rows:
        name = _metric_name(row)
        value = _metric_value(row)
        if name is not None and value is not None:
            grouped.setdefault(name, []).append(value)
    series = tuple(
        GPUTraceMetricSeries(name, tuple(values))
        for name, values in sorted(grouped.items())
    )
    return GPUTraceTable(schema, len(rows), series)


def _trace_size(trace: pathlib.Path) -> int:
    if trace.is_file():
        return trace.stat().st_size
    if trace.is_dir():
        return sum(path.stat().st_size for path in trace.rglob("*") if path.is_file())
    raise RuntimeError(f"The WebKit GPU trace is missing: {trace}")


def collect_gpu_trace_report(
    *,
    task_root: pathlib.Path,
    trace: pathlib.Path,
    gpu_process_id: int,
    duration: float,
) -> GPUTraceReport:
    owned_trace = validate_owned_path(task_root, trace)
    trace_bytes = _trace_size(owned_trace)
    if trace_bytes <= 0:
        raise RuntimeError("The WebKit GPU trace contains no data.")

    tables: list[GPUTraceTable] = []
    diagnostics: list[str] = []
    for index, schema in enumerate(GPU_TRACE_SCHEMAS):
        output = validate_owned_path(task_root, task_root / f"gpu-metrics-{index}.xml")
        result = subprocess.run(
            gpu_trace_export_command(
                task_root=task_root,
                trace=owned_trace,
                output=output,
                schema=schema,
            ),
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            detail = result.stderr.strip().splitlines()[-1:] or ["no diagnostic"]
            diagnostics.append(f"{schema}: export status {result.returncode} ({detail[0]})")
            continue
        if not output.is_file():
            diagnostics.append(f"{schema}: export produced no XML file")
            continue
        try:
            table = parse_gpu_metric_table(output.read_text(errors="replace"), schema=schema)
        except (ET.ParseError, ValueError) as error:
            diagnostics.append(f"{schema}: {error}")
            continue
        diagnostics.append(
            f"{schema}: {table.row_count} rows, {len(table.series)} numeric series"
        )
        if table.row_count > 0 and table.series:
            tables.append(table)

    if not tables:
        raise RuntimeError(
            "The exact WebKit GPU trace exported no numeric Game Performance metrics.\n"
            + "\n".join(diagnostics)
        )
    return GPUTraceReport(
        process_id=gpu_process_id,
        duration_seconds=duration,
        trace_bytes=trace_bytes,
        tables=tuple(tables),
    )


def release_build_command(
    *,
    repository_root: pathlib.Path,
    task_root: pathlib.Path,
    derived_data: pathlib.Path,
) -> list[str]:
    owned_derived_data = validate_owned_path(task_root, derived_data)
    return [
        "xcodebuild",
        "-project",
        str(repository_root.resolve() / "Crest.xcodeproj"),
        "-scheme",
        "Crest",
        "-configuration",
        "Release",
        "-destination",
        "platform=macOS,arch=arm64",
        "-derivedDataPath",
        str(owned_derived_data),
        f"PRODUCT_BUNDLE_IDENTIFIER={PERFORMANCE_BUNDLE_ID}",
        f"PRODUCT_NAME={PERFORMANCE_PRODUCT_NAME}",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) CREST_PERFORMANCE_HARNESS",
        "build",
    ]


def parse_footprint_output(output: str) -> FootprintMeasurement:
    current_match = re.search(r"^\s*phys_footprint:\s*(\d+)\s+B\s*$", output, re.MULTILINE)
    peak_match = re.search(r"^\s*phys_footprint_peak:\s*(\d+)\s+B\s*$", output, re.MULTILINE)
    if current_match is None:
        raise ValueError("Physical footprint is missing from footprint output.")
    if peak_match is None:
        raise ValueError("Physical footprint peak is missing from footprint output.")
    return FootprintMeasurement(
        current_bytes=int(current_match.group(1)),
        peak_bytes=int(peak_match.group(1)),
    )


def parse_web_content_process_ids(output: str) -> set[int]:
    process_ids = {
        int(match.group(1))
        for match in re.finditer(
            r"^[ \t]*CREST_PERFORMANCE_WEB_CONTENT_PID=(\d+)[ \t]*$",
            output,
            re.MULTILINE,
        )
    }
    return {process_id for process_id in process_ids if process_id > 0}


def summarize_samples(samples: Sequence[ReleaseSoakSample]) -> dict[str, int]:
    if not samples:
        raise ValueError("At least one soak sample is required.")
    active_samples = [sample for sample in samples if sample.phase == "active"]
    idle_samples = [sample for sample in samples if sample.phase == "idle"]
    if not active_samples or not idle_samples:
        raise ValueError("Both active and idle soak samples are required.")
    idle_start = idle_samples[0].aggregate_bytes
    idle_end = idle_samples[-1].aggregate_bytes
    return {
        "sampleCount": len(samples),
        "sampleHighWaterBytes": max(sample.aggregate_bytes for sample in samples),
        "activeHighWaterBytes": max(sample.aggregate_bytes for sample in active_samples),
        "idleHighWaterBytes": max(sample.aggregate_bytes for sample in idle_samples),
        "idleStartBytes": idle_start,
        "idleEndBytes": idle_end,
        "idleDeltaBytes": idle_end - idle_start,
    }


def performance_application_path(derived_data: pathlib.Path) -> pathlib.Path:
    return (
        derived_data
        / "Build"
        / "Products"
        / "Release"
        / f"{PERFORMANCE_PRODUCT_NAME}.app"
    )


def _build_release(
    *,
    repository_root: pathlib.Path,
    task_root: pathlib.Path,
    derived_data: pathlib.Path,
) -> pathlib.Path:
    log_path = validate_owned_path(task_root, task_root / "release-build.log")
    command = release_build_command(
        repository_root=repository_root,
        task_root=task_root,
        derived_data=derived_data,
    )
    with log_path.open("wb") as build_log:
        result = subprocess.run(
            command,
            cwd=repository_root,
            stdout=build_log,
            stderr=subprocess.STDOUT,
            check=False,
        )
    if result.returncode != 0:
        tail = "\n".join(log_path.read_text(errors="replace").splitlines()[-80:])
        raise RuntimeError(f"The signed Release soak build failed:\n{tail}")
    application = performance_application_path(derived_data)
    if not application.is_dir():
        raise RuntimeError(f"The signed Release product is missing: {application}")
    _verify_performance_application(application)
    return application


def prepare_application(
    *,
    repository_root: pathlib.Path,
    task_root: pathlib.Path,
    derived_data: pathlib.Path,
    prebuilt_application: pathlib.Path | None,
) -> pathlib.Path:
    if prebuilt_application is None:
        return _build_release(
            repository_root=repository_root,
            task_root=task_root,
            derived_data=derived_data,
        )
    application = prebuilt_application.resolve()
    if not application.is_dir():
        raise RuntimeError(f"The prebuilt signed Release product is missing: {application}")
    _verify_performance_application(application)
    return application


def _verify_performance_application(application: pathlib.Path) -> None:
    info_path = application / "Contents" / "Info.plist"
    with info_path.open("rb") as info_file:
        info = plistlib.load(info_file)
    if info.get("CFBundleIdentifier") != PERFORMANCE_BUNDLE_ID:
        raise RuntimeError("The soak product does not use its dedicated bundle identifier.")
    subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", str(application)],
        text=True,
        capture_output=True,
        check=True,
    )


def _application_executable(application: pathlib.Path) -> pathlib.Path:
    info_path = application / "Contents" / "Info.plist"
    with info_path.open("rb") as info_file:
        executable_name = plistlib.load(info_file).get("CFBundleExecutable")
    if not isinstance(executable_name, str) or not executable_name:
        raise RuntimeError("The soak product has no declared executable.")
    executable = application / "Contents" / "MacOS" / executable_name
    if not executable.is_file():
        raise RuntimeError(f"The soak executable is missing: {executable}")
    return executable


def _webkit_processes() -> dict[int, str]:
    result = subprocess.run(
        ["ps", "-axo", "pid=,command="],
        text=True,
        capture_output=True,
        check=True,
    )
    processes: dict[int, str] = {}
    for line in result.stdout.splitlines():
        fields = line.strip().split(maxsplit=1)
        if len(fields) != 2 or not any(marker in fields[1] for marker in WEBKIT_PROCESS_MARKERS):
            continue
        processes[int(fields[0])] = fields[1]
    return processes


def _process_references_bundle(pid: int, bundle_id: str) -> bool:
    result = subprocess.run(
        ["lsof", "-p", str(pid)],
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0 and bundle_id in result.stdout


def _webkit_role(command: str) -> str:
    if "WebContent.xpc" in command:
        return "web-content"
    if "Networking.xpc" in command:
        return "networking"
    if "GPU.xpc" in command:
        return "gpu"
    return "webkit"


def _reported_web_content_processes(application_log: pathlib.Path) -> set[int]:
    if not application_log.is_file():
        return set()
    return parse_web_content_process_ids(application_log.read_text(errors="replace"))


def _owned_webkit_processes(
    baseline: set[int],
    application_log: pathlib.Path,
) -> dict[int, str]:
    current = _webkit_processes()
    reported_web_content = _reported_web_content_processes(application_log)
    return {
        pid: _webkit_role(command)
        for pid, command in current.items()
        if pid not in baseline
        and (
            ("WebContent.xpc" in command and pid in reported_web_content)
            or _process_references_bundle(pid, PERFORMANCE_BUNDLE_ID)
        )
    }


def _measure_process(pid: int, role: str) -> ProcessFootprint | None:
    result = subprocess.run(
        ["footprint", "-f", "bytes", "-p", str(pid)],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    try:
        measurement = parse_footprint_output(result.stdout)
    except ValueError:
        return None
    return ProcessFootprint(
        pid=pid,
        role=role,
        current_bytes=measurement.current_bytes,
        peak_bytes=measurement.peak_bytes,
    )


def _sample_processes(
    main_pid: int,
    baseline: set[int],
    application_log: pathlib.Path,
) -> tuple[ProcessFootprint, ...]:
    main = _measure_process(main_pid, "main")
    if main is None:
        raise RuntimeError("The signed Release main process could not be measured.")
    auxiliaries = _owned_webkit_processes(baseline, application_log)
    measurements = [main]
    for pid, role in sorted(auxiliaries.items()):
        if measurement := _measure_process(pid, role):
            measurements.append(measurement)
    return tuple(measurements)


def _wait_for_window(process_name: str, timeout: float = 15) -> None:
    environment = os.environ.copy()
    environment["CREST_SOAK_PROCESS_NAME"] = process_name
    script = """
        set processName to system attribute "CREST_SOAK_PROCESS_NAME"
        tell application "System Events"
          repeat 150 times
            if exists process processName then
              tell process processName
                set frontmost to true
                if (count windows) > 0 then return
              end tell
            end if
            delay 0.1
          end repeat
          error "The signed Release soak window did not appear."
        end tell
        """
    subprocess.run(
        ["osascript", "-"],
        input=script,
        text=True,
        capture_output=True,
        env=environment,
        timeout=timeout + 2,
        check=True,
    )


def _select_next_tab(process_name: str) -> None:
    environment = os.environ.copy()
    environment["CREST_SOAK_PROCESS_NAME"] = process_name
    script = """
        set processName to system attribute "CREST_SOAK_PROCESS_NAME"
        tell application "System Events"
          tell process processName
            set frontmost to true
            keystroke "]" using {command down, shift down}
          end tell
        end tell
        """
    subprocess.run(
        ["osascript", "-"],
        input=script,
        text=True,
        capture_output=True,
        env=environment,
        timeout=5,
        check=True,
    )


def _wait_for_initial_fixture(server: FixtureServer, timeout: float = 15) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if any(target.startswith("/performance.html?") for target in server.network_metrics().requests):
            return
        time.sleep(0.1)
    raise TimeoutError("The signed Release app did not load the first performance page.")


def _warm_pages(process_name: str, tab_count: int, server: FixtureServer) -> None:
    _wait_for_initial_fixture(server)
    for _ in range(tab_count - 1):
        _select_next_tab(process_name)
        time.sleep(0.5)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        targets = {
            target
            for target in server.network_metrics().requests
            if target.startswith("/performance.html?")
        }
        if len(targets) >= tab_count:
            return
        time.sleep(0.2)
    raise TimeoutError(f"Only {len(targets)} of {tab_count} performance pages loaded.")


def _wait_for_reported_web_content(
    application_log: pathlib.Path,
    baseline: set[int],
    timeout: float = 10,
) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        reported = _reported_web_content_processes(application_log)
        current = _webkit_processes()
        if any(
            process_id not in baseline
            and process_id in current
            and "WebContent.xpc" in current[process_id]
            for process_id in reported
        ):
            return
        time.sleep(0.1)
    raise RuntimeError("Crest did not report its live WebContent process identifier.")


def _record_phase(
    *,
    phase: str,
    duration: float,
    sample_interval: float,
    process: subprocess.Popen[bytes],
    process_name: str,
    baseline: set[int],
    application_log: pathlib.Path,
    started_at: float,
    samples: list[ReleaseSoakSample],
) -> None:
    phase_end = time.monotonic() + duration
    next_sample = time.monotonic()
    next_cycle = time.monotonic()
    while time.monotonic() < phase_end:
        if process.poll() is not None:
            raise RuntimeError("The signed Release app exited during the soak.")
        now = time.monotonic()
        if phase == "active" and now >= next_cycle:
            _select_next_tab(process_name)
            next_cycle = now + 0.75
        if now >= next_sample:
            sample = ReleaseSoakSample(
                elapsed_seconds=now - started_at,
                phase=phase,
                processes=_sample_processes(process.pid, baseline, application_log),
            )
            samples.append(sample)
            print(
                f"{phase} {sample.elapsed_seconds:.1f}s "
                f"{sample.aggregate_bytes / (1024 * 1024):.1f} MiB "
                f"across {len(sample.processes)} processes",
                flush=True,
            )
            next_sample = now + sample_interval
        time.sleep(min(0.1, max(phase_end - time.monotonic(), 0)))
    final_elapsed = time.monotonic() - started_at
    if not samples or samples[-1].phase != phase or final_elapsed - samples[-1].elapsed_seconds > 1:
        samples.append(
            ReleaseSoakSample(
                elapsed_seconds=final_elapsed,
                phase=phase,
                processes=_sample_processes(process.pid, baseline, application_log),
            )
        )


def _terminate_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=8)
        return
    except (ProcessLookupError, subprocess.TimeoutExpired):
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        pass


def _wait_for_auxiliary_exit(
    baseline: set[int],
    application_log: pathlib.Path,
) -> None:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if not _owned_webkit_processes(baseline, application_log):
            return
        time.sleep(0.2)
    for pid in _owned_webkit_processes(baseline, application_log):
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass


def _unregister_application(application: pathlib.Path) -> None:
    launch_services = pathlib.Path(
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/"
        "LaunchServices.framework/Support/lsregister"
    )
    if launch_services.is_file():
        subprocess.run(
            [str(launch_services), "-u", str(application)],
            capture_output=True,
            check=False,
        )


def performance_state_paths() -> tuple[pathlib.Path, ...]:
    library = pathlib.Path.home() / "Library"
    return (
        library / "Containers" / PERFORMANCE_BUNDLE_ID,
        library / "Application Scripts" / PERFORMANCE_BUNDLE_ID,
        library / "Preferences" / f"{PERFORMANCE_BUNDLE_ID}.plist",
        library / "HTTPStorages" / PERFORMANCE_BUNDLE_ID,
        library / "Caches" / PERFORMANCE_BUNDLE_ID,
        library / "Saved Application State" / f"{PERFORMANCE_BUNDLE_ID}.savedState",
    )


def _ensure_clean_performance_state() -> None:
    leftovers = [path for path in performance_state_paths() if path.exists()]
    if leftovers:
        rendered = "\n".join(f"  {path}" for path in leftovers)
        raise RuntimeError(f"Dedicated soak state already exists; refusing to overwrite it:\n{rendered}")


def _move_protected_container_to_trash(path: pathlib.Path) -> None:
    expected_name = path.name
    subprocess.run(
        ["open", "-a", "Finder", str(path)],
        text=True,
        capture_output=True,
        check=True,
    )
    environment = os.environ.copy()
    environment["CREST_SOAK_CLEANUP_NAME"] = expected_name
    script = """
        set expectedName to system attribute "CREST_SOAK_CLEANUP_NAME"
        tell application "Finder"
          activate
          repeat 200 times
            if (count windows) > 0 and name of front window is expectedName then
              tell application "System Events" to key code 51 using {command down}
              delay 0.5
              return
            end if
            delay 0.1
          end repeat
          error "Finder did not open the exact dedicated soak container."
        end tell
        """
    result = subprocess.run(
        ["osascript", "-"],
        input=script,
        text=True,
        capture_output=True,
        env=environment,
        timeout=25,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or "Finder cleanup returned no diagnostic."
        raise RuntimeError(f"Finder could not trash the protected soak container: {detail}")
    if path.exists():
        raise RuntimeError(f"Finder did not move the protected soak container: {path}")


def _remove_performance_state() -> None:
    subprocess.run(
        ["defaults", "delete", PERFORMANCE_BUNDLE_ID],
        capture_output=True,
        check=False,
    )
    for path in performance_state_paths():
        if path.is_dir():
            try:
                shutil.rmtree(path)
            except PermissionError:
                _move_protected_container_to_trash(path)
        elif path.exists():
            path.unlink()


def _launch_environment(server: FixtureServer, tab_count: int, run_id: str) -> dict[str, str]:
    environment = os.environ.copy()
    environment.update(
        {
            "CREST_RESET_SESSION": "1",
            "CREST_USE_IN_MEMORY_CREDENTIALS": "1",
            "CREST_PERFORMANCE_BASE_URL": f"{server.base_url}/",
            "CREST_PERFORMANCE_TAB_COUNT": str(tab_count),
            "CREST_PERFORMANCE_RUN_ID": run_id,
        }
    )
    return environment


def process_selection_description() -> str:
    return (
        "main PID; WebContent PIDs declared by the performance-only WKWebView "
        "_webProcessIdentifier probe; and post-launch GPU/networking processes whose "
        f"open files contain the dedicated {PERFORMANCE_BUNDLE_ID} sandbox identity"
    )


def _report(
    *,
    active_duration: float,
    idle_duration: float,
    sample_interval: float,
    tab_count: int,
    build_source: str,
    samples: list[ReleaseSoakSample],
    server: FixtureServer,
    gpu_trace: GPUTraceReport | None = None,
) -> dict[str, Any]:
    report: dict[str, Any] = {
        "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "build": {
            "configuration": "Release",
            "architecture": "arm64",
            "signed": True,
            "bundleIdentifier": PERFORMANCE_BUNDLE_ID,
            "compilationCondition": "CREST_PERFORMANCE_HARNESS",
            "source": build_source,
        },
        "workload": {
            "tabCount": tab_count,
            "activeDurationSeconds": active_duration,
            "idleDurationSeconds": idle_duration,
            "sampleIntervalSeconds": sample_interval,
            "content": "loopback performance.html with mutation and muted video",
            "spaceCount": 1,
            "profileCount": 1,
        },
        "processSelection": process_selection_description(),
        "network": server.network_metrics().as_json(),
        "summary": summarize_samples(samples),
        "samples": [sample.as_json() for sample in samples],
    }
    if gpu_trace is not None:
        report["gpuTrace"] = gpu_trace.as_json()
    return report


def _wait_for_gpu_trace(
    process: subprocess.Popen[bytes],
    *,
    duration: float,
    log_path: pathlib.Path,
) -> None:
    try:
        return_code = process.wait(timeout=max(duration + 15, 20))
    except subprocess.TimeoutExpired as error:
        _terminate_process(process)
        raise RuntimeError("The exact WebKit GPU trace exceeded its bounded timeout.") from error
    if return_code == 0:
        return
    tail = ""
    if log_path.is_file():
        tail = "\n".join(log_path.read_text(errors="replace").splitlines()[-40:])
    detail = f"\n{tail}" if tail else ""
    raise RuntimeError(f"The exact WebKit GPU trace failed with status {return_code}.{detail}")


def run_soak(
    *,
    repository_root: pathlib.Path,
    active_duration: float,
    idle_duration: float,
    sample_interval: float,
    tab_count: int,
    gpu_trace_duration: float = 0,
    prebuilt_application: pathlib.Path | None = None,
) -> dict[str, Any]:
    _ensure_clean_performance_state()
    with tempfile.TemporaryDirectory(prefix="crest-release-soak-", dir="/private/tmp") as raw_root:
        task_root = pathlib.Path(raw_root).resolve()
        derived_data = validate_owned_path(task_root, task_root / "DerivedData")
        server = FixtureServer(task_root)
        application: pathlib.Path | None = None
        process: subprocess.Popen[bytes] | None = None
        application_output: Any | None = None
        gpu_trace_process: subprocess.Popen[bytes] | None = None
        gpu_trace_output: Any | None = None
        gpu_trace_report: GPUTraceReport | None = None
        application_log = validate_owned_path(task_root, task_root / "application.log")
        gpu_trace_log = validate_owned_path(task_root, task_root / "gpu-trace.log")
        gpu_trace_path = validate_owned_path(task_root, task_root / "WebKitGPU.trace")
        baseline = set(_webkit_processes())
        try:
            if prebuilt_application is None:
                print("Building isolated signed Release product…", flush=True)
            else:
                print("Verifying prebuilt isolated signed Release product…", flush=True)
            application = prepare_application(
                repository_root=repository_root,
                task_root=task_root,
                derived_data=derived_data,
                prebuilt_application=prebuilt_application,
            )
            server.start()
            server.reset_network_metrics()
            run_id = datetime.datetime.now(datetime.timezone.utc).strftime(
                "release-%Y%m%dT%H%M%SZ"
            )
            executable = _application_executable(application)
            application_output = application_log.open("wb")
            process = subprocess.Popen(
                [str(executable)],
                env=_launch_environment(server, tab_count, run_id),
                stdout=application_output,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            process_name = executable.name
            _wait_for_window(process_name)
            print(f"Warming {tab_count} retained pages…", flush=True)
            _warm_pages(process_name, tab_count, server)
            _wait_for_reported_web_content(application_log, baseline)
            gpu_process_id: int | None = None
            if gpu_trace_duration > 0:
                gpu_process_id = select_owned_gpu_process_id(
                    _owned_webkit_processes(baseline, application_log)
                )
                print(
                    f"Tracing exact task-owned WebKit GPU process {gpu_process_id} "
                    f"for {gpu_trace_duration:g}s…",
                    flush=True,
                )
                gpu_trace_output = gpu_trace_log.open("wb")
                gpu_trace_process = subprocess.Popen(
                    gpu_trace_command(
                        task_root=task_root,
                        trace=gpu_trace_path,
                        gpu_process_id=gpu_process_id,
                        duration=gpu_trace_duration,
                    ),
                    stdout=gpu_trace_output,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
            samples: list[ReleaseSoakSample] = []
            started_at = time.monotonic()
            _record_phase(
                phase="active",
                duration=active_duration,
                sample_interval=sample_interval,
                process=process,
                process_name=process_name,
                baseline=baseline,
                application_log=application_log,
                started_at=started_at,
                samples=samples,
            )
            if gpu_trace_process is not None and gpu_process_id is not None:
                _wait_for_gpu_trace(
                    gpu_trace_process,
                    duration=gpu_trace_duration,
                    log_path=gpu_trace_log,
                )
                gpu_trace_process = None
                if gpu_trace_output is not None:
                    gpu_trace_output.close()
                    gpu_trace_output = None
                gpu_trace_report = collect_gpu_trace_report(
                    task_root=task_root,
                    trace=gpu_trace_path,
                    gpu_process_id=gpu_process_id,
                    duration=gpu_trace_duration,
                )
            _record_phase(
                phase="idle",
                duration=idle_duration,
                sample_interval=sample_interval,
                process=process,
                process_name=process_name,
                baseline=baseline,
                application_log=application_log,
                started_at=started_at,
                samples=samples,
            )
            return _report(
                active_duration=active_duration,
                idle_duration=idle_duration,
                sample_interval=sample_interval,
                tab_count=tab_count,
                build_source="built" if prebuilt_application is None else "prebuilt-verified",
                samples=samples,
                server=server,
                gpu_trace=gpu_trace_report,
            )
        finally:
            if gpu_trace_process is not None:
                _terminate_process(gpu_trace_process)
            if gpu_trace_output is not None:
                gpu_trace_output.close()
            if process is not None:
                _terminate_process(process)
            if application_output is not None:
                application_output.close()
            _wait_for_auxiliary_exit(baseline, application_log)
            server.stop()
            if application is not None:
                _unregister_application(application)
            _remove_performance_state()


def parse_arguments(arguments: Sequence[str]) -> Any:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--active-duration", type=float, default=180)
    parser.add_argument("--idle-duration", type=float, default=420)
    parser.add_argument("--sample-interval", type=float, default=15)
    parser.add_argument("--tab-count", type=int, default=13)
    parser.add_argument(
        "--gpu-trace-duration",
        type=float,
        default=0,
        help="Trace the exact task-owned WebKit GPU XPC process during the active phase.",
    )
    parser.add_argument(
        "--application",
        type=pathlib.Path,
        help="Reuse an already-built dedicated signed Release app after verifying it.",
    )
    parser.add_argument("--output", type=pathlib.Path)
    parsed = parser.parse_args(arguments)
    if parsed.active_duration <= 0 or parsed.idle_duration <= 0:
        parser.error("Active and idle durations must be positive.")
    if parsed.sample_interval <= 0:
        parser.error("Sample interval must be positive.")
    if parsed.gpu_trace_duration < 0:
        parser.error("GPU trace duration cannot be negative.")
    if parsed.gpu_trace_duration > parsed.active_duration:
        parser.error("GPU trace duration must fit inside the active phase.")
    if not 2 <= parsed.tab_count <= 24:
        parser.error("Tab count must be between 2 and 24.")
    return parsed


def _install_signal_handlers() -> None:
    def interrupt(signum: int, frame: object) -> None:
        raise KeyboardInterrupt(f"Interrupted by signal {signum}")

    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(signum, interrupt)


def main(arguments: Sequence[str] | None = None) -> int:
    parsed = parse_arguments(arguments if arguments is not None else sys.argv[1:])
    _install_signal_handlers()
    try:
        report = run_soak(
            repository_root=pathlib.Path(__file__).resolve().parents[1],
            active_duration=parsed.active_duration,
            idle_duration=parsed.idle_duration,
            sample_interval=parsed.sample_interval,
            tab_count=parsed.tab_count,
            gpu_trace_duration=parsed.gpu_trace_duration,
            prebuilt_application=parsed.application,
        )
    except (KeyboardInterrupt, OSError, RuntimeError, subprocess.SubprocessError, TimeoutError) as error:
        print(f"Release soak failed: {error}", file=sys.stderr)
        return 1
    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if parsed.output is None:
        sys.stdout.write(rendered)
    else:
        parsed.output.write_text(rendered, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
