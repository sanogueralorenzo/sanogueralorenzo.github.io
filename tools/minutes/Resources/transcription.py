"""Local Moonshine transcription of saved, bounded audio segments."""
import array
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import wave
from files import atomic


def transcribe(folder, model_config):
    transcript = folder / "transcript.txt"
    if transcript.exists():
        return transcript.read_text()
    from moonshine_voice import Transcriber, ModelArch
    audio = sorted((folder / "audio").glob("*.caf"))
    if not audio:
        raise ValueError("No saved audio is available. Check microphone and screen/audio permissions.")
    cache = folder / "transcription"
    cache.mkdir(exist_ok=True)
    entries = []
    with Transcriber(model_path=model_config["path"], model_arch=ModelArch(model_config["arch"])) as engine:
        for path in audio:
            cached = cache / (path.stem + ".json")
            if cached.exists():
                entries.extend(json.loads(cached.read_text()))
                continue
            source, offset, _ = path.stem.split("_")
            offset = float(offset)
            with tempfile.TemporaryDirectory(prefix="minutes-audio-") as tmp:
                wav = Path(tmp) / "audio.wav"
                subprocess.run(["/usr/bin/afconvert", str(path), str(wav), "-f", "WAVE", "-d", "LEI16@16000", "-c", "1"], check=True, capture_output=True, timeout=120)
                # Each capture segment is at most 60 seconds, bounding inference memory.
                with wave.open(str(wav)) as stream:
                    samples = array.array("h", stream.readframes(stream.getnframes()))
                if sys.byteorder != "little":
                    samples.byteswap()
                lines = engine.transcribe_without_streaming([x / 32768 for x in samples], sample_rate=16000).lines
                segment = [{"time": offset + line.start_time, "source": source, "text": line.text.strip()} for line in lines if line.text.strip()]
            atomic(cached, json.dumps(segment))
            entries.extend(segment)
            atomic(folder / "progress.txt", f"Transcribing · {len(list(cache.glob('*.json')))}/{len(audio)}")
    entries.sort(key=lambda entry: entry["time"])
    text = "\n".join(f"[{int(e['time']) // 60:02d}:{int(e['time']) % 60:02d}] {e['source']}: {e['text']}" for e in entries)
    if not text.strip():
        raise ValueError("No speech was recognized. Audio is saved; check capture permissions and microphone input.")
    atomic(transcript, text)
    return text

