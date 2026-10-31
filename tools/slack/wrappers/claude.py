#!/usr/bin/env python3
"""Normalize Claude's final answer and session ID. Optional argument: session ID."""

import json
import subprocess
import sys


def main():
    if len(sys.argv) > 2:
        raise ValueError("Usage: claude.py [session_id]")
    command = ["claude", "-p", "--output-format", "json"]
    if len(sys.argv) == 2:
        command.extend(["--resume", sys.argv[1]])
    result = subprocess.run(command, input=sys.stdin.read(), capture_output=True, text=True)
    try:
        response = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"claude CLI did not return JSON: {result.stderr[-1500:]}") from error
    if result.returncode or response.get("is_error"):
        detail = response.get("result") or result.stderr[-1500:]
        raise RuntimeError(f"claude CLI failed (exit {result.returncode}): {detail}")
    print(json.dumps({"session_id": response.get("session_id"), "answer": response.get("result")}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
