#!/usr/bin/env python3
"""Build an externally prepared Chromium baseline without exhausting the host disk."""

import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--ninja", default="ninja")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--target", default="chrome", help="Ninja target; defaults to the complete browser")
    parser.add_argument("--min-free-gib", type=int, default=15)
    args = parser.parse_args()
    root = args.source.resolve()
    repo = Path(__file__).resolve().parents[2]
    if root == repo or repo in root.parents:
        parser.error("Chromium source and products must be outside the Crest checkout")
    if not (root / "out/CrestBaseline/build.ninja").is_file():
        parser.error("Prepare the pinned source and generate out/CrestBaseline first")
    if args.jobs < 1 or args.min_free_gib < 1:
        parser.error("Job count and disk reserve must be positive")
    reserve = args.min_free_gib * 1024**3
    if shutil.disk_usage(root).free < reserve:
        parser.error("Free disk space is below the requested reserve")

    process = subprocess.Popen(
        [args.ninja, "-C", "out/CrestBaseline", f"-j{args.jobs}", args.target],
        cwd=root, start_new_session=True,
    )

    def stop(signum=signal.SIGTERM, _frame=None):
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()

    for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(signum, stop)
    try:
        while process.poll() is None:
            if shutil.disk_usage(root).free < reserve:
                print(f"Stopped Chromium build to preserve {args.min_free_gib} GiB free disk space.", flush=True)
                stop()
                return 75
            time.sleep(2)
        return process.returncode
    finally:
        stop()


if __name__ == "__main__":
    raise SystemExit(main())
