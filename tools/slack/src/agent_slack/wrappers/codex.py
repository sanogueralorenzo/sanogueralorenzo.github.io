"""Normalize Codex's final answer and session ID. Optional argument: session ID."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def run():
    if len(sys.argv) > 2:
        raise ValueError("Usage: agent-slack-codex [session_id]")
    with tempfile.TemporaryDirectory(prefix="agent-slack-codex-") as directory:
        answer_path = Path(directory) / "answer"
        common = ["--json", "-o", str(answer_path), "--skip-git-repo-check"]
        if len(sys.argv) == 2:
            command = ["codex", "exec", "resume", *common, sys.argv[1], "-"]
        else:
            command = ["codex", "exec", *common, "-C", os.getcwd(), "-"]
        result = subprocess.run(command, input=sys.stdin.read(), capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(f"codex exec failed (exit {result.returncode}): {result.stderr[-1500:]}")
        session_id = None
        for line in result.stdout.split("\n"):
            if line.startswith("{"):
                event = json.loads(line)
                if event.get("type") == "thread.started":
                    session_id = event.get("thread_id")
                    break
        print(json.dumps({"session_id": session_id, "answer": answer_path.read_text()}))


def main():
    try:
        run()
    except (OSError, ValueError, RuntimeError) as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
