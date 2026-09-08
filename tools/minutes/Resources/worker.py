"""Run the saved-audio pipeline under one meeting lock."""
import argparse
import json
import os
from pathlib import Path
import sys
from files import atomic
from notes import body, summarize
from pi_processor import stop_active
from transcription import transcribe


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    parser.add_argument("settings", type=Path)
    parser.add_argument("model", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    folder = args.folder
    # A forced app exit must not leave a provider running or racing a retry after restart.
    import signal
    def cancel(signum, frame):
        raise SystemExit(1)
    signal.signal(signal.SIGTERM, cancel)
    import fcntl
    import threading
    import time
    lock = (folder / "processing.lock").open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        atomic(folder / "error.txt", "This meeting is still being processed. Wait a moment and retry.")
        return 1
    parent = os.getppid()
    def watch_parent():
        while True:
            time.sleep(1)
            if os.getppid() != parent:
                stop_active()
                os._exit(1)
    threading.Thread(target=watch_parent, daemon=True).start()
    try:
        settings = json.loads(args.settings.read_text())
        atomic(folder / "progress.txt", "Transcribing locally…")
        text = transcribe(folder, json.loads(args.model.read_text()))
        atomic(folder / "progress.txt", "Writing note…")
        note = summarize(text, settings, folder)
        # App commits title/body into its meeting metadata only after this file is complete.
        atomic(folder / "result.json", json.dumps({"title": note["title"], "body": body(note)}, ensure_ascii=False))
    except Exception as error:
        atomic(folder / "error.txt", str(error))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
