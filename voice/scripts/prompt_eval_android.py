#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

ACTION_RUN = "com.sanogueralorenzo.voice.DEBUG_PROMPT_BENCHMARK_RUN"
DEFAULT_PACKAGE = "com.sanogueralorenzo.voice"
DEFAULT_RECEIVER = (
    "com.sanogueralorenzo.voice/com.sanogueralorenzo.voice.setup.benchmark.PromptBenchmarkAdbReceiver"
)
DEFAULT_RESULTS_DIR = "benchmark_runs"
APP_DEFAULT_PROMPT_SENTINEL = "__APP_DEFAULT__"


def run(cmd: list[str], *, stdin_path: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    stdin = None
    try:
        if stdin_path is not None:
            stdin = stdin_path.open("rb")
        completed = subprocess.run(
            cmd,
            stdin=stdin,
            capture_output=True,
            text=True,
            check=False,
        )
    finally:
        if stdin is not None:
            stdin.close()
    if check and completed.returncode != 0:
        raise RuntimeError(
            f"Command failed ({completed.returncode}): {' '.join(cmd)}\n"
            f"stdout:\n{completed.stdout}\n"
            f"stderr:\n{completed.stderr}"
        )
    return completed


def adb_cmd(serial: str | None, *args: str) -> list[str]:
    base = ["adb"]
    if serial:
        base += ["-s", serial]
    base += list(args)
    return base


def detect_device(serial: str | None) -> str:
    out = run(["adb", "devices"], check=True).stdout.splitlines()
    devices = []
    for line in out[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            devices.append(parts[0])
    if serial:
        if serial not in devices:
            raise RuntimeError(f"Device serial not found/ready: {serial}. connected={devices}")
        return serial
    if len(devices) == 0:
        raise RuntimeError("No connected Android devices.")
    if len(devices) > 1:
        raise RuntimeError(f"Multiple devices connected {devices}. Pass --serial.")
    return devices[0]


def ensure_package_installed(serial: str, package_name: str) -> None:
    result = run(adb_cmd(serial, "shell", "pm", "path", package_name), check=False)
    if result.returncode != 0 or "package:" not in result.stdout:
        raise RuntimeError(
            f"Package {package_name} not installed on {serial}. "
            "Install debug app first with ./gradlew :app:installDebug"
        )


def wake_app_process(serial: str, package_name: str) -> None:
    run(
        adb_cmd(
            serial,
            "shell",
            "monkey",
            "-p",
            package_name,
            "-c",
            "android.intent.category.LAUNCHER",
            "1",
        ),
        check=True,
    )


def run_as_shell(serial: str, package_name: str, shell_command: str, *, stdin_path: Path | None = None) -> subprocess.CompletedProcess[str]:
    return run(
        adb_cmd(serial, "shell", f"run-as {package_name} sh -c '{shell_command}'"),
        stdin_path=stdin_path,
        check=True,
    )


def upload_file_to_app(serial: str, package_name: str, local_path: Path, rel_path: str) -> None:
    parent = os.path.dirname(rel_path)
    if parent:
        run_as_shell(serial, package_name, f"mkdir -p files/{parent}")
    run_as_shell(
        serial,
        package_name,
        f"cat > files/{rel_path}",
        stdin_path=local_path,
    )


def read_file_from_app(serial: str, package_name: str, rel_path: str, *, check: bool = True) -> str:
    result = run(adb_cmd(serial, "shell", f"run-as {package_name} cat files/{rel_path}"), check=False)
    if check and result.returncode != 0:
        raise RuntimeError(
            f"Failed reading files/{rel_path} via run-as.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result.stdout


def load_prompt_text(prompt_path: Path) -> str:
    raw = prompt_path.read_text(encoding="utf-8")
    if prompt_path.suffix.lower() != ".json":
        return raw
    payload = json.loads(raw)
    version = str(payload.get("version", "")).strip()
    prompt = str(payload.get("prompt", "")).strip()
    if not version:
        raise ValueError(f"Invalid prompt JSON (missing version): {prompt_path}")
    if not prompt:
        raise ValueError(f"Invalid prompt JSON (missing prompt): {prompt_path}")
    return prompt + "\n"


def trigger_run(
    serial: str,
    package_name: str,
    receiver_component: str,
    run_id: str,
    prompt_rel_path: str,
    dataset_rel_path: str,
    output_rel_path: str,
) -> None:
    cmd = adb_cmd(
        serial,
        "shell",
        "am",
        "broadcast",
        "-a",
        ACTION_RUN,
        "-n",
        receiver_component,
        "--es",
        "run_id",
        run_id,
        "--es",
        "prompt_rel_path",
        prompt_rel_path,
        "--es",
        "dataset_rel_path",
        dataset_rel_path,
        "--es",
        "output_rel_path",
        output_rel_path,
    )
    run(cmd, check=True)


def poll_status(
    serial: str,
    package_name: str,
    status_rel_path: str,
    timeout_sec: int,
    poll_interval_sec: float,
) -> dict:
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        status_raw = read_file_from_app(serial, package_name, status_rel_path, check=False).strip()
        if status_raw:
            try:
                payload = json.loads(status_raw)
            except json.JSONDecodeError:
                payload = {}
            state = str(payload.get("state", "")).lower()
            if state in ("completed", "failed"):
                return payload
        time.sleep(poll_interval_sec)
    raise TimeoutError(f"Timed out waiting for status file files/{status_rel_path}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run prompt benchmark on Android device via adb.")
    prompt_group = parser.add_mutually_exclusive_group(required=True)
    prompt_group.add_argument("--prompt-file")
    prompt_group.add_argument("--use-app-default-prompt", action="store_true")
    parser.add_argument("--cases-file", required=True)
    parser.add_argument("--serial", default="")
    parser.add_argument("--package", default=DEFAULT_PACKAGE)
    parser.add_argument("--receiver-component", default=DEFAULT_RECEIVER)
    parser.add_argument("--run-id", default="")
    parser.add_argument("--timeout-sec", type=int, default=900)
    parser.add_argument("--poll-interval-sec", type=float, default=1.0)
    parser.add_argument("--report-file", default=".cache/prompt_eval_android/report.txt")
    parser.add_argument("--json-report-file", default=".cache/prompt_eval_android/report.json")
    args = parser.parse_args()

    prompt_file = Path(args.prompt_file).resolve() if args.prompt_file else None
    cases_file = Path(args.cases_file).resolve()
    if prompt_file is not None and not prompt_file.exists():
        raise FileNotFoundError(f"Prompt file not found: {prompt_file}")
    if not cases_file.exists():
        raise FileNotFoundError(f"Cases file not found: {cases_file}")

    serial = detect_device(args.serial.strip() or None)
    ensure_package_installed(serial, args.package)
    wake_app_process(serial, args.package)

    run_id = args.run_id.strip() or datetime.now().strftime("run_%Y%m%d_%H%M%S")
    prompt_rel = APP_DEFAULT_PROMPT_SENTINEL
    dataset_rel = f"{DEFAULT_RESULTS_DIR}/{run_id}.dataset.jsonl"
    output_rel = f"{DEFAULT_RESULTS_DIR}/{run_id}.result.json"
    status_rel = f"{DEFAULT_RESULTS_DIR}/{run_id}.status.json"
    report_rel = f"{DEFAULT_RESULTS_DIR}/{run_id}.report.txt"

    if prompt_file is not None:
        prompt_text = load_prompt_text(prompt_file)
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as temp_prompt:
            temp_prompt.write(prompt_text)
            temp_prompt_path = Path(temp_prompt.name)
        prompt_rel = f"{DEFAULT_RESULTS_DIR}/{run_id}.prompt.txt"
        try:
            upload_file_to_app(serial, args.package, temp_prompt_path, prompt_rel)
        finally:
            temp_prompt_path.unlink(missing_ok=True)
    upload_file_to_app(serial, args.package, cases_file, dataset_rel)
    trigger_run(
        serial=serial,
        package_name=args.package,
        receiver_component=args.receiver_component,
        run_id=run_id,
        prompt_rel_path=prompt_rel,
        dataset_rel_path=dataset_rel,
        output_rel_path=output_rel,
    )

    status = poll_status(
        serial=serial,
        package_name=args.package,
        status_rel_path=status_rel,
        timeout_sec=args.timeout_sec,
        poll_interval_sec=args.poll_interval_sec,
    )
    state = str(status.get("state", "")).lower()
    if state != "completed":
        err = status.get("error", "unknown")
        raise RuntimeError(f"Benchmark failed on device state={state} error={err}")

    result_raw = read_file_from_app(serial, args.package, output_rel, check=True)
    result_json = json.loads(result_raw)
    report_text = read_file_from_app(serial, args.package, report_rel, check=False)

    report_file = Path(args.report_file).resolve()
    json_report_file = Path(args.json_report_file).resolve()
    report_file.parent.mkdir(parents=True, exist_ok=True)
    json_report_file.parent.mkdir(parents=True, exist_ok=True)
    if report_text.strip():
        report_file.write_text(report_text, encoding="utf-8")
    else:
        report_file.write_text(json.dumps(result_json, indent=2), encoding="utf-8")
    json_report_file.write_text(json.dumps(result_json, indent=2), encoding="utf-8")

    summary = result_json.get("summary", {})
    pass_count = int(summary.get("pass_count", 0))
    fail_count = int(summary.get("fail_count", 0))
    total_cases = int(summary.get("total_cases", pass_count + fail_count))
    pass_rate = float(summary.get("pass_rate", 0.0))
    print(
        f"Device benchmark completed serial={serial} total={total_cases} "
        f"pass={pass_count} fail={fail_count} pass_rate={pass_rate:.2f}%"
    )
    print(f"Text report: {report_file}")
    print(f"JSON report: {json_report_file}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        raise
