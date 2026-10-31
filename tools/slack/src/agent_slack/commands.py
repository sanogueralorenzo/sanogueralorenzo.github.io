"""Configured executables that accept stdin and return an answer/session JSON object."""

import json
import os
import shutil
from dataclasses import dataclass

from .process_runner import ProcessRunner


@dataclass(frozen=True)
class Command:
    start: tuple[str, ...]
    resume: tuple[str, ...]

    @property
    def key(self):
        return json.dumps([self.start, self.resume], separators=(",", ":"))


def load_commands():
    config = json.loads(os.environ.get("AGENT_SLACK_COMMANDS", "{}"))
    if not isinstance(config, dict) or not config:
        raise ValueError("AGENT_SLACK_COMMANDS must map keywords to start and resume commands")
    commands = {}
    for keyword, entry in config.items():
        if not keyword or not keyword.isprintable() or any(character.isspace() for character in keyword):
            raise ValueError("Command keywords must be nonempty words without whitespace")
        keyword = keyword.casefold()
        if keyword in commands:
            raise ValueError(f"Command keywords must be unique ignoring case: {keyword}")
        if not isinstance(entry, dict) or set(entry) != {"start", "resume"}:
            raise ValueError(f"Keyword {keyword} requires start and resume argument arrays")
        resolved = {}
        for mode in ("start", "resume"):
            args = entry[mode]
            if not isinstance(args, list) or not args or any(not isinstance(arg, str) or "\0" in arg for arg in args):
                raise ValueError(f"Keyword {keyword}: {mode} must be a nonempty array of strings")
            if ("{session_id}" in args) != (mode == "resume"):
                raise ValueError(f"Keyword {keyword}: only resume must contain a {{session_id}} argument")
            executable = shutil.which(args[0]) if args[0] else None
            if not executable:
                raise ValueError(f"Keyword {keyword}: executable not found: {args[0]}")
            # Resolve before switching to the selected workspace.
            resolved[mode] = (os.path.abspath(executable), *args[1:])
        commands[keyword] = Command(**resolved)
    return commands


class Executor:
    def __init__(self, processes: ProcessRunner):
        self.processes = processes

    def run(self, command: Command, prompt: str, workspace, session_id=None) -> tuple[str, str]:
        args = command.resume if session_id else command.start
        args = [session_id if arg == "{session_id}" else arg for arg in args]
        result = self.processes.run(
            args, prompt, workspace,
            env={key: value for key, value in os.environ.items()
                 if not key.startswith(("SLACK_", "AGENT_SLACK_"))},
        )
        if result.returncode:
            raise RuntimeError(f"Command failed (exit {result.returncode}): {result.stderr[-1500:]}")
        try:
            response = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            raise RuntimeError("Command must return a JSON object with session_id and answer") from error
        if not isinstance(response, dict):
            raise RuntimeError("Command must return a JSON object with session_id and answer")
        returned, answer = response.get("session_id"), response.get("answer")
        if not isinstance(returned, str) or not returned.strip():
            raise RuntimeError("Command returned no session ID")
        if session_id and returned != session_id:
            raise RuntimeError("Command resumed a different session")
        if not isinstance(answer, str) or not answer.strip():
            raise RuntimeError("Command returned an empty final answer")
        return returned, answer.strip()
