#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <rust_log_file> <ts_log_file>" >&2
  exit 1
fi

RUST_LOG_FILE="$1"
TS_LOG_FILE="$2"

if [[ ! -f "$RUST_LOG_FILE" ]]; then
  echo "Missing file: $RUST_LOG_FILE" >&2
  exit 1
fi

if [[ ! -f "$TS_LOG_FILE" ]]; then
  echo "Missing file: $TS_LOG_FILE" >&2
  exit 1
fi

python3 - "$RUST_LOG_FILE" "$TS_LOG_FILE" <<'PY'
import re
import statistics
import sys
from pathlib import Path

log_files = [Path(sys.argv[1]), Path(sys.argv[2])]
pattern = re.compile(
    r"BENCHMARK_REPLY\s+runtime=(?P<runtime>\w+)\s+kind=(?P<kind>\w+)\s+chat_id=(?P<chat_id>[-\w]+)\s+message_id=(?P<message_id>[-\w]+)\s+status=(?P<status>\w+)\s+elapsed_ms=(?P<elapsed_ms>\d+)"
)

def percentile(values, p):
    if not values:
        return None
    if len(values) == 1:
        return float(values[0])
    values = sorted(values)
    idx = (len(values) - 1) * p
    lo = int(idx)
    hi = min(lo + 1, len(values) - 1)
    frac = idx - lo
    return values[lo] * (1 - frac) + values[hi] * frac

metrics = {
    "rust": {"ok": [], "errors": 0, "total": 0},
    "ts": {"ok": [], "errors": 0, "total": 0},
}

for file_path in log_files:
    for line in file_path.read_text(errors="ignore").splitlines():
        match = pattern.search(line)
        if not match:
            continue
        runtime = match.group("runtime")
        if runtime not in metrics:
            continue
        status = match.group("status")
        elapsed = int(match.group("elapsed_ms"))
        metrics[runtime]["total"] += 1
        if status == "ok":
            metrics[runtime]["ok"].append(elapsed)
        else:
            metrics[runtime]["errors"] += 1

print("| runtime | samples(ok/total) | errors | p50 (ms) | p95 (ms) | p99 (ms) | avg (ms) | max (ms) |")
print("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")

for runtime in ("rust", "ts"):
    data = metrics[runtime]
    ok = data["ok"]
    total = data["total"]
    errors = data["errors"]

    if ok:
        p50 = percentile(ok, 0.50)
        p95 = percentile(ok, 0.95)
        p99 = percentile(ok, 0.99)
        avg = statistics.fmean(ok)
        max_v = max(ok)
        print(
            f"| {runtime} | {len(ok)}/{total} | {errors} | {p50:.2f} | {p95:.2f} | {p99:.2f} | {avg:.2f} | {max_v:.2f} |"
        )
    else:
        print(f"| {runtime} | 0/{total} | {errors} | - | - | - | - | - |")

print("")
print(f"Rust log: {log_files[0]}")
print(f"TS log: {log_files[1]}")
PY
