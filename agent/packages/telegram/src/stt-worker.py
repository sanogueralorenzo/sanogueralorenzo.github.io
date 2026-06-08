#!/usr/bin/env python3
import json
import os
import sys
import traceback

_model = None
_model_name = None


def _load_model(model_name: str):
    global _model, _model_name
    if _model is not None and _model_name == model_name:
        return _model
    from faster_whisper import WhisperModel

    compute_type = os.getenv("PI_CHAT_STT_COMPUTE_TYPE", "int8")
    device = os.getenv("PI_CHAT_STT_DEVICE", "cpu")
    _model = WhisperModel(model_name, device=device, compute_type=compute_type)
    _model_name = model_name
    print(json.dumps({"type": "ready", "model": model_name}), flush=True)
    return _model


def _transcribe(path: str, model_name: str, language: str | None):
    model = _load_model(model_name)
    kwargs = {"vad_filter": True}
    if language:
        kwargs["language"] = language
    segments, info = model.transcribe(path, **kwargs)
    text = " ".join(segment.text.strip() for segment in segments).strip()
    return {"text": text, "language": getattr(info, "language", None)}


for line in sys.stdin:
    try:
        request = json.loads(line)
        request_id = request.get("id")
        path = request["path"]
        model_name = request.get("model") or os.getenv("PI_CHAT_STT_MODEL", "base")
        language = request.get("language", os.getenv("PI_CHAT_STT_LANGUAGE", "en")) or None
        result = _transcribe(path, model_name, language)
        print(json.dumps({"id": request_id, "ok": True, **result}), flush=True)
    except Exception as exc:
        traceback.print_exc(file=sys.stderr)
        print(json.dumps({"id": request.get("id") if "request" in locals() else None, "ok": False, "error": str(exc)}), flush=True)
