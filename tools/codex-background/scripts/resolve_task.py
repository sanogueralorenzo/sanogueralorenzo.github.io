#!/usr/bin/env python3
"""Resolve a pending desktop task by its unique dispatch marker in saved history."""

import argparse
import json
import os
import re
import secrets
import sys
from pathlib import Path


TASK_ID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


def session_root():
    return Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")) / "sessions"


def has_initial_prompt_marker(path, marker):
    with path.open(encoding="utf-8") as stream:
        for index, line in enumerate(stream):
            if index >= 100:
                break
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                break  # A task may still be writing its last line.
            payload = entry.get("payload", {})
            if entry.get("type") != "response_item":
                continue
            if payload.get("type") == "function_call_output" and payload.get("name") == "create_thread":
                if marker in payload.get("output", ""):
                    return True
    return False


def resolve(token, since):
    marker = f"[codex-background-id: {token}]"
    matches = []
    for path in session_root().rglob("rollout-*.jsonl"):
        try:
            if path.stat().st_mtime < since:
                continue
            match = TASK_ID.search(path.stem)
            if match and has_initial_prompt_marker(path, marker):
                matches.append(match.group())
        except FileNotFoundError:
            continue
    if len(matches) > 1:
        raise RuntimeError(f"Dispatch marker matched {len(matches)} tasks; refusing to guess")
    return matches[0] if matches else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    subcommands.add_parser("new", help="Print a new dispatch token")
    lookup = subcommands.add_parser("resolve", help="Find a task with the marker in its first prompt")
    lookup.add_argument("token", help="Token printed by the new command")
    lookup.add_argument("--since", type=float, required=True, help="Dispatch start time as Unix seconds")
    args = parser.parse_args()
    if args.command == "new":
        print(secrets.token_hex(8))
        return
    if not re.fullmatch(r"[0-9a-f]{16}", args.token):
        parser.error("token must be 16 lowercase hexadecimal characters")
    task_id = resolve(args.token, args.since)
    print(json.dumps({"taskId": task_id, "pending": task_id is None}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, json.JSONDecodeError) as error:
        print(f"resolve_task: {error}", file=sys.stderr)
        sys.exit(1)
