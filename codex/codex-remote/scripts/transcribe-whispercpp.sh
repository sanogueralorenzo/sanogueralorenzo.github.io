#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <audio-file>" >&2
  exit 1
fi

resolve_whisper_cli() {
  if [[ -n "${WHISPER_CLI_BIN:-}" ]]; then
    if [[ -x "${WHISPER_CLI_BIN}" ]]; then
      printf "%s\n" "${WHISPER_CLI_BIN}"
      return 0
    fi
    return 1
  fi

  if command -v whisper-cli >/dev/null 2>&1; then
    command -v whisper-cli
    return 0
  fi

  local candidate=""
  for candidate in \
    "/opt/homebrew/bin/whisper-cli" \
    "/usr/local/bin/whisper-cli" \
    "$HOME/.local/bin/whisper-cli" \
    "$HOME/bin/whisper-cli"; do
    if [[ -x "$candidate" ]]; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done

  if command -v brew >/dev/null 2>&1; then
    local brew_prefix=""
    brew_prefix="$(brew --prefix whisper-cpp 2>/dev/null || true)"
    if [[ -n "$brew_prefix" && -x "$brew_prefix/bin/whisper-cli" ]]; then
      printf "%s\n" "$brew_prefix/bin/whisper-cli"
      return 0
    fi
  fi

  return 1
}

resolve_ffmpeg_bin() {
  if command -v ffmpeg >/dev/null 2>&1; then
    command -v ffmpeg
    return 0
  fi

  local candidate=""
  for candidate in \
    "/opt/homebrew/bin/ffmpeg" \
    "/usr/local/bin/ffmpeg" \
    "$HOME/.local/bin/ffmpeg" \
    "$HOME/bin/ffmpeg"; do
    if [[ -x "$candidate" ]]; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done

  return 1
}

whisper_cli="$(resolve_whisper_cli || true)"
if [[ -z "$whisper_cli" ]]; then
  echo "whisper-cli not found. Install whisper.cpp, put whisper-cli in PATH, or set WHISPER_CLI_BIN." >&2
  echo "Checked PATH and common locations (/opt/homebrew/bin, /usr/local/bin, \$HOME/.local/bin, \$HOME/bin)." >&2
  exit 1
fi

ffmpeg_bin="$(resolve_ffmpeg_bin || true)"
if [[ -z "$ffmpeg_bin" ]]; then
  echo "ffmpeg not found. Install ffmpeg and ensure it is in PATH." >&2
  echo "Checked PATH and common locations (/opt/homebrew/bin, /usr/local/bin, \$HOME/.local/bin, \$HOME/bin)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
default_model_path="${PROJECT_ROOT}/models/ggml-tiny.en.bin"
model_path="${WHISPER_MODEL_PATH_TINY:-$default_model_path}"
if [[ ! -f "$model_path" && -f "$default_model_path" ]]; then
  model_path="$default_model_path"
fi
if [[ ! -f "$model_path" ]]; then
  echo "Whisper model not found. Checked:" >&2
  echo "- WHISPER_MODEL_PATH_TINY=${WHISPER_MODEL_PATH_TINY:-<unset>}" >&2
  echo "- default=${default_model_path}" >&2
  exit 1
fi

input_file="$1"
if [[ ! -f "$input_file" ]]; then
  echo "Input file not found: $input_file" >&2
  exit 1
fi

tmp_base="$(mktemp /tmp/tg-whisper-XXXXXX)"
cleanup() {
  rm -f "${tmp_base}" "${tmp_base}.txt" "${tmp_base}.wav"
}
trap cleanup EXIT

wav_input="${tmp_base}.wav"
"$ffmpeg_bin" -y -loglevel error -i "$input_file" -ar 16000 -ac 1 -c:a pcm_s16le "$wav_input"

# whisper-cli writes transcript to <output>.txt when using -otxt -of.
"$whisper_cli" -m "$model_path" -f "$wav_input" -t 4 -l en -otxt -of "$tmp_base" -np >/dev/null 2>&1

if [[ ! -f "${tmp_base}.txt" ]]; then
  echo "whisper-cli did not produce a transcript file." >&2
  exit 1
fi

cat "${tmp_base}.txt"
