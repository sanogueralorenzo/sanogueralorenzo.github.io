#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <rust|ts> [duration_seconds]" >&2
  exit 1
fi

RUNTIME="$1"
DURATION_SECONDS="${2:-120}"
START_TIMEOUT_SECONDS="${START_TIMEOUT_SECONDS:-45}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$PROJECT_ROOT/runtime/bench}"

if ! [[ "$DURATION_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "duration_seconds must be a positive integer" >&2
  exit 1
fi

if [[ "$DURATION_SECONDS" -lt 10 ]]; then
  echo "duration_seconds must be at least 10" >&2
  exit 1
fi

if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
  echo "Missing .env in $PROJECT_ROOT" >&2
  echo "Create it with: cp .env.example .env" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$OUT_DIR/reply-latency-${RUNTIME}-${TIMESTAMP}.log"

case "$RUNTIME" in
  rust)
    if ! command -v cargo >/dev/null 2>&1; then
      echo "cargo not found" >&2
      exit 1
    fi
    if [[ ! -x "$PROJECT_ROOT/target/release/gateway" ]]; then
      echo "Building Rust release binary..."
      (cd "$PROJECT_ROOT" && cargo build --release >/dev/null)
    fi
    READY_PATTERN="Telegram polling started as @"
    CMD="cd '$PROJECT_ROOT' && RUST_LOG=info BENCHMARK_REPLY_LATENCY=true target/release/gateway"
    ;;
  ts)
    if ! command -v node >/dev/null 2>&1; then
      echo "node not found" >&2
      exit 1
    fi
    if [[ ! -f "$PROJECT_ROOT/dist/index.js" ]]; then
      echo "Missing dist/index.js" >&2
      exit 1
    fi
    READY_PATTERN="Telegram polling started as @"
    CMD="cd '$PROJECT_ROOT' && BENCHMARK_REPLY_LATENCY=true node dist/index.js"
    ;;
  *)
    echo "Unknown runtime: $RUNTIME (expected rust or ts)" >&2
    exit 1
    ;;
esac

cleanup() {
  local pid="$1"
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    sleep 1
  fi
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi
  wait "$pid" >/dev/null 2>&1 || true
}

bash -lc "$CMD" >"$LOG_FILE" 2>&1 &
PID=$!

STARTED_AT="$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"

READY=0
while true; do
  if grep -q "$READY_PATTERN" "$LOG_FILE"; then
    READY=1
    break
  fi

  if ! kill -0 "$PID" >/dev/null 2>&1; then
    break
  fi

  NOW="$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"

  if (( NOW - STARTED_AT >= START_TIMEOUT_SECONDS * 1000 )); then
    break
  fi

  sleep 0.1
done

if (( READY == 0 )); then
  cleanup "$PID"
  echo "Runtime failed to become ready. Last log lines:" >&2
  tail -n 20 "$LOG_FILE" >&2 || true
  echo "Log file: $LOG_FILE" >&2
  exit 1
fi

echo "Recording $RUNTIME reply latency for ${DURATION_SECONDS}s..."
echo "Send the same prompt set you want to compare during this window."
sleep "$DURATION_SECONDS"
cleanup "$PID"

echo "Saved log: $LOG_FILE"
echo "Next: ./scripts/compare-reply-latency.sh <rust_log> <ts_log>"
