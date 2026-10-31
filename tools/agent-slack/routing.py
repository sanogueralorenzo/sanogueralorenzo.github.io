"""Choose a configured command and workspace from an authorized Slack message."""

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path

from commands import Command


@dataclass(frozen=True)
class Request:
    command: Command
    workspace: Path | None
    request: str


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
    selected = commands.get(parts[0])
    if selected is None:
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
    return Request(selected, workspace, request)


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
