#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <audio-file>" >&2
  exit 1
fi

if ! command -v whisper-cli >/dev/null 2>&1; then
  echo "whisper-cli not found. Install whisper.cpp and ensure whisper-cli is in PATH." >&2
  exit 1
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg not found. Install ffmpeg and ensure it is in PATH." >&2
  exit 1
fi

: "${WHISPER_MODEL_PATH_TINY:?Set WHISPER_MODEL_PATH_TINY to your local ggml-tiny(.en).bin path.}"
model_path="$WHISPER_MODEL_PATH_TINY"
if [[ ! -f "$model_path" ]]; then
  echo "Whisper model not found: $model_path" >&2
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
ffmpeg -y -loglevel error -i "$input_file" -ar 16000 -ac 1 -c:a pcm_s16le "$wav_input"

# whisper-cli writes transcript to <output>.txt when using -otxt -of.
whisper-cli -m "$model_path" -f "$wav_input" -t 4 -l en -otxt -of "$tmp_base" -np >/dev/null 2>&1

if [[ ! -f "${tmp_base}.txt" ]]; then
  echo "whisper-cli did not produce a transcript file." >&2
  exit 1
fi

cat "${tmp_base}.txt"
