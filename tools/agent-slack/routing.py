"""Choose a CLI from the prefix and a workspace from project aliases."""

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Command:
    provider: str
    workspace: Path | None
    request: str


def command_providers():
    commands = json.loads(os.environ.get("AGENT_SLACK_COMMANDS", "{}"))
    if not isinstance(commands, dict) or not commands:
        raise ValueError("AGENT_SLACK_COMMANDS must map at least one keyword to a CLI name")
    for keyword, provider in commands.items():
        if not keyword or not keyword.isprintable() or any(character.isspace() for character in keyword):
            raise ValueError("Command keywords must be nonempty words without whitespace")
        if provider not in ("codex", "claude"):
            raise ValueError(f"Keyword {keyword} requires provider codex or claude")
    return commands


def project_workspaces():
    projects = json.loads(os.environ.get("AGENT_SLACK_PROJECTS", "{}"))
    if not isinstance(projects, dict):
        raise ValueError("AGENT_SLACK_PROJECTS must be a JSON object mapping aliases to directories")
    result = {}
    for alias, directory in projects.items():
        if not re.fullmatch(r"[a-z][a-z0-9_-]*", alias) or not isinstance(directory, str) or not directory.strip():
            raise ValueError("Project aliases must be lowercase words with nonempty directory paths")
        result[alias] = Path(directory).expanduser().resolve()
        if not result[alias].is_dir():
            raise ValueError(f"Project directory does not exist for alias {alias}")
    return result


def command(text, projects, commands):
    if not text or text[0].isspace():
        return None
    parts = text.split(maxsplit=1)
    provider = commands.get(parts[0])
    if provider is None:
        return None
    request = parts[1].strip() if len(parts) == 2 else ""
    if not request:
        return None
    workspace = None
    first = len(request)
    for alias, directory in projects.items():
        match = re.search(rf"(?<![\w-]){re.escape(alias)}(?![\w-])", request, re.IGNORECASE)
        if match and match.start() < first:
            first = match.start()
            workspace = directory
    return Command(provider, workspace, request)


def command_for(event, user_id, projects, commands):
    if (
        event.get("type") == "message"
        and event.get("subtype") in (None, "thread_broadcast")
        and not event.get("bot_id")
        and not event.get("app_id")
        and event.get("user") == user_id
        and bool(event.get("channel") and event.get("ts"))
    ):
        return command(event.get("text", ""), projects, commands)
    return None
