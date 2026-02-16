#!/usr/bin/env bash
set -euo pipefail

MODEL_URL_DEFAULT="https://huggingface.co/ANISH-j/models-for-echo-application/resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm"
LITERT_REPO_URL="https://github.com/google-ai-edge/LiteRT-LM.git"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CACHE_DIR="${ROOT_DIR}/.cache/prompt_eval"

PROMPT_FILE=""
CASES_FILE=""
MODEL_URL="${MODEL_URL_DEFAULT}"
MODEL_PATH="${CACHE_DIR}/models/Gemma3-1B-IT_multi-prefill-seq_q4_ekv4096.litertlm"
LITERTLM_DIR="${CACHE_DIR}/LiteRT-LM"
BINARY_PATH=""
BACKEND="cpu"
MAX_CASES=0
TIMEOUT_SEC=240
REPORT_FILE="${CACHE_DIR}/report.txt"
JSON_REPORT_FILE="${CACHE_DIR}/report.json"
SKIP_SETUP=0
SKIP_DOWNLOAD=0
NO_UPDATE=0

usage() {
  cat <<EOF
Usage:
  scripts/prompt_eval.sh --prompt-file <path> --cases-file <path> [options]

Required:
  --prompt-file <path>       Prompt template file. Use {{input}} placeholder if needed.
  --cases-file <path>        JSONL/JSON cases with: id,input,expected,match.

Options:
  --backend <cpu|gpu>        Runtime backend (default: cpu)
  --max-cases <N>            Run only first N cases (default: 0 = all)
  --timeout-sec <N>          Per-case timeout in seconds (default: 240)
  --report-file <path>       Text report path (default: .cache/prompt_eval/report.txt)
  --json-report-file <path>  JSON report path (default: .cache/prompt_eval/report.json)
  --model-path <path>        Model path (default inside .cache)
  --model-url <url>          Model download URL
  --litertlm-dir <path>      LiteRT-LM checkout location
  --binary-path <path>       Use existing binary; skips build if provided
  --skip-setup               Skip clone/build step
  --skip-download            Skip model download step
  --no-update                Do not run git pull when LiteRT-LM already exists
  -h, --help                 Show this help
EOF
}

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing dependency: $name" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file)
      PROMPT_FILE="$2"
      shift 2
      ;;
    --cases-file)
      CASES_FILE="$2"
      shift 2
      ;;
    --backend)
      BACKEND="$2"
      shift 2
      ;;
    --max-cases)
      MAX_CASES="$2"
      shift 2
      ;;
    --timeout-sec)
      TIMEOUT_SEC="$2"
      shift 2
      ;;
    --report-file)
      REPORT_FILE="$2"
      shift 2
      ;;
    --json-report-file)
      JSON_REPORT_FILE="$2"
      shift 2
      ;;
    --model-path)
      MODEL_PATH="$2"
      shift 2
      ;;
    --model-url)
      MODEL_URL="$2"
      shift 2
      ;;
    --litertlm-dir)
      LITERTLM_DIR="$2"
      shift 2
      ;;
    --binary-path)
      BINARY_PATH="$2"
      shift 2
      ;;
    --skip-setup)
      SKIP_SETUP=1
      shift
      ;;
    --skip-download)
      SKIP_DOWNLOAD=1
      shift
      ;;
    --no-update)
      NO_UPDATE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${PROMPT_FILE}" || -z "${CASES_FILE}" ]]; then
  echo "--prompt-file and --cases-file are required" >&2
  usage
  exit 1
fi

if [[ ! -f "${PROMPT_FILE}" ]]; then
  echo "Prompt file not found: ${PROMPT_FILE}" >&2
  exit 1
fi

if [[ ! -f "${CASES_FILE}" ]]; then
  echo "Cases file not found: ${CASES_FILE}" >&2
  exit 1
fi

require_cmd python3
require_cmd git
require_cmd curl
mkdir -p "${CACHE_DIR}"

if [[ "${SKIP_DOWNLOAD}" -eq 0 ]]; then
  mkdir -p "$(dirname "${MODEL_PATH}")"
  if [[ ! -f "${MODEL_PATH}" ]]; then
    echo "Downloading model to ${MODEL_PATH}"
    curl -fL --retry 3 --retry-all-errors -o "${MODEL_PATH}" "${MODEL_URL}"
  else
    echo "Model already exists at ${MODEL_PATH}"
  fi
fi

if [[ -z "${BINARY_PATH}" ]]; then
  BINARY_PATH="${LITERTLM_DIR}/bazel-bin/runtime/engine/litert_lm_advanced_main"
fi

if [[ "${SKIP_SETUP}" -eq 0 ]]; then
  if [[ ! -d "${LITERTLM_DIR}/.git" ]]; then
    echo "Cloning LiteRT-LM into ${LITERTLM_DIR}"
    mkdir -p "$(dirname "${LITERTLM_DIR}")"
    git clone --depth 1 "${LITERT_REPO_URL}" "${LITERTLM_DIR}"
  elif [[ "${NO_UPDATE}" -eq 0 ]]; then
    echo "Updating LiteRT-LM checkout"
    git -C "${LITERTLM_DIR}" pull --ff-only
  fi

  if command -v bazelisk >/dev/null 2>&1; then
    BAZEL_BIN="bazelisk"
  elif command -v bazel >/dev/null 2>&1; then
    BAZEL_BIN="bazel"
  else
    echo "Missing bazel or bazelisk. Install one first (e.g. brew install bazelisk)." >&2
    exit 1
  fi

  echo "Building LiteRT-LM advanced CLI"
  (
    cd "${LITERTLM_DIR}"
    "${BAZEL_BIN}" build //runtime/engine:litert_lm_advanced_main
  )
fi

if [[ ! -x "${BINARY_PATH}" ]]; then
  echo "LiteRT-LM binary not found or not executable: ${BINARY_PATH}" >&2
  exit 1
fi

mkdir -p "$(dirname "${REPORT_FILE}")"
mkdir -p "$(dirname "${JSON_REPORT_FILE}")"

echo "Running prompt evaluation with runtime default sampling"
python3 "${SCRIPT_DIR}/prompt_eval_runner.py" \
  --binary-path "${BINARY_PATH}" \
  --model-path "${MODEL_PATH}" \
  --prompt-file "${PROMPT_FILE}" \
  --cases-file "${CASES_FILE}" \
  --backend "${BACKEND}" \
  --report-file "${REPORT_FILE}" \
  --json-report-file "${JSON_REPORT_FILE}" \
  --max-cases "${MAX_CASES}" \
  --timeout-sec "${TIMEOUT_SEC}" \
  --verbose

echo "Done."
echo "Text report: ${REPORT_FILE}"
echo "JSON report: ${JSON_REPORT_FILE}"
