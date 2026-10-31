"""Choose a CLI profile from the prefix and a workspace from project aliases."""

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path


PREFIX = re.compile(r"^(bot|chat|claude)(?:\s+|$)")
PROFILES = {
    "bot": (None, None, None),
    "chat": ("codex", "gpt-6.1-sol", "high"),
    "claude": ("claude", "claude-opus-5-5", "high"),
}


@dataclass(frozen=True)
class Command:
    provider: str | None
    model: str | None
    effort: str | None
    workspace: Path | None
    request: str


def project_workspaces():
    projects = json.loads(os.environ.get("SLACK_REPLY_PROJECTS", "{}"))
    if not isinstance(projects, dict):
        raise ValueError("SLACK_REPLY_PROJECTS must be a JSON object mapping aliases to directories")
    result = {}
    for alias, directory in projects.items():
        if not re.fullmatch(r"[a-z][a-z0-9_-]*", alias) or not isinstance(directory, str) or not directory.strip():
            raise ValueError("Project aliases must be lowercase words with nonempty directory paths")
        result[alias] = Path(directory).expanduser().resolve()
        if not result[alias].is_dir():
            raise ValueError(f"Project directory does not exist for alias {alias}")
    return result


def command(text, projects):
    prefix = PREFIX.match(text)
    if not prefix:
        return None
    request = text[prefix.end():].strip()
    if not request:
        return None
    workspace = None
    first = len(request)
    for alias, directory in projects.items():
        match = re.search(rf"(?<![\w-]){re.escape(alias)}(?![\w-])", request, re.IGNORECASE)
        if match and match.start() < first:
            first = match.start()
            workspace = directory
    return Command(*PROFILES[prefix.group(1)], workspace, request)


def eligible(event, user_id):
    return (
        event.get("type") == "message"
        and event.get("subtype") in (None, "thread_broadcast")
        and not event.get("bot_id")
        and not event.get("app_id")
        and event.get("user") == user_id
        and PREFIX.match(event.get("text", "")) is not None
        and bool(event.get("channel") and event.get("ts"))
    )
