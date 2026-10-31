"""Choose a CLI profile from the prefix and a workspace from project aliases."""

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path

from providers import ProviderSettings


@dataclass(frozen=True)
class Command:
    settings: ProviderSettings
    workspace: Path | None
    request: str


def command_profiles():
    profiles = json.loads(os.environ.get("SLACK_REPLY_COMMANDS", "{}"))
    if not isinstance(profiles, dict) or not profiles:
        raise ValueError("SLACK_REPLY_COMMANDS must map at least one keyword to CLI settings")
    result = {}
    for keyword, settings in profiles.items():
        if not keyword or not keyword.isprintable() or any(character.isspace() for character in keyword):
            raise ValueError("Command keywords must be nonempty words without whitespace")
        if not isinstance(settings, dict) or settings.keys() - {"provider", "model", "reasoning_effort", "tier"}:
            raise ValueError(f"Invalid CLI settings for keyword {keyword}")
        if settings.get("provider") not in ("codex", "claude", "pi"):
            raise ValueError(f"Keyword {keyword} requires provider codex, claude, or pi")
        for field in ("model", "reasoning_effort"):
            if not isinstance(settings.get(field, ""), str):
                raise ValueError(f"Keyword {keyword} requires a string {field}")
        if "tier" in settings and settings["tier"] not in ("default", "fast"):
            raise ValueError(f"Keyword {keyword} tier must be default or fast")
        result[keyword] = ProviderSettings(settings["provider"], settings.get("model", "").strip(),
                                           settings.get("reasoning_effort", "").strip(), settings.get("tier"))
    return result


def prefix(text, profiles):
    if not text or text[0].isspace():
        return None
    parts = text.split(maxsplit=1)
    return profiles.get(parts[0])


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


def command(text, projects, profiles):
    settings = prefix(text, profiles)
    if settings is None:
        return None
    parts = text.split(maxsplit=1)
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
    return Command(settings, workspace, request)


def eligible(event, user_id, profiles):
    return (
        event.get("type") == "message"
        and event.get("subtype") in (None, "thread_broadcast")
        and not event.get("bot_id")
        and not event.get("app_id")
        and event.get("user") == user_id
        and prefix(event.get("text", ""), profiles) is not None
        and bool(event.get("channel") and event.get("ts"))
    )
