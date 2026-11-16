"""Normalize Claude's final answer, session ID, and safe failures."""

import json
import subprocess
import sys

from errors import HookError, classify, report


def run():
    if len(sys.argv) > 2:
        raise HookError("invalid_response", "Claude")
    command = ["claude", "-p", "--output-format", "json"]
    if len(sys.argv) == 2:
        command.extend(["--resume", sys.argv[1]])
    try:
        result = subprocess.run(
            command, input=sys.stdin.read(), capture_output=True, text=True
        )
    except FileNotFoundError:
        raise HookError("missing_cli", "Claude") from None
    try:
        response = json.loads(result.stdout)
    except ValueError:
        if result.returncode:
            raise classify(result.stderr + "\n" + result.stdout, "Claude") from None
        raise HookError("invalid_response", "Claude") from None
    if not isinstance(response, dict):
        raise HookError("invalid_response", "Claude")
    if result.returncode or response.get("is_error"):
        raise classify(str(response.get("result", "")) + "\n" + result.stderr, "Claude")
    print(
        json.dumps(
            {"session_id": response.get("session_id"), "answer": response.get("result")}
        )
    )


if __name__ == "__main__":
    try:
        run()
    except (OSError, ValueError, RuntimeError) as error:
        raise SystemExit(report(error))
