#!/usr/bin/env python3
"""Reject private assistant state, machine state, and signing material from Git."""

from __future__ import annotations

import os
from pathlib import Path, PurePosixPath
import subprocess
import sys


REPOSITORY_ROOT = Path(
    os.environ.get(
        "CREST_PUBLIC_SOURCE_REPOSITORY_ROOT",
        Path(__file__).resolve().parent.parent,
    )
)

# The public contribution instructions are the only tracked assistant files:
# the root AGENTS.md, the crest-contribution skill, and its Claude Code link.
PUBLIC_INSTRUCTION_PATHS = {
    "AGENTS.md",
    ".claude/skills/crest-contribution",
}
PUBLIC_INSTRUCTION_PREFIXES = (".agents/skills/crest-contribution/",)

FORBIDDEN_NAMES = {
    ".cursorrules",
    "agent.md",
    "agents.md",
    "claude.md",
    "claude.local.md",
    "copilot-instructions.md",
    "design-qa.md",
    "gemini.md",
}
FORBIDDEN_COMPONENTS = {
    ".agents",
    ".claude",
    ".codex",
    ".crest-review",
    ".cursor",
    ".idea",
    ".vscode",
    "xcuserdata",
}
SIGNING_SUFFIXES = {
    ".csr",
    ".mobileprovision",
    ".p12",
    ".p8",
    ".provisionprofile",
}


def violation_reason(relative_path: str) -> str | None:
    if relative_path in PUBLIC_INSTRUCTION_PATHS or relative_path.startswith(
        PUBLIC_INSTRUCTION_PREFIXES
    ):
        return None

    path = PurePosixPath(relative_path)
    lowered_parts = tuple(part.lower() for part in path.parts)
    lowered_name = path.name.lower()

    if lowered_name in FORBIDDEN_NAMES:
        return "assistant-only or private working instruction file"
    if any(
        component in FORBIDDEN_COMPONENTS or component.startswith(".codex-")
        for component in lowered_parts
    ):
        return "machine-local editor or assistant state"
    if path.suffix.lower() in SIGNING_SUFFIXES:
        return "signing credential or provisioning material"
    if lowered_name == ".ds_store":
        return "machine-local Finder state"
    if lowered_name == ".env" or (
        lowered_name.startswith(".env.") and lowered_name != ".env.example"
    ):
        return "local environment configuration"
    return None


def tracked_paths(repository_root: Path) -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=repository_root,
        capture_output=True,
        check=True,
    )
    return [
        path.decode("utf-8", errors="surrogateescape")
        for path in result.stdout.split(b"\0")
        if path
    ]


def main() -> int:
    violations = [
        (path, reason)
        for path in tracked_paths(REPOSITORY_ROOT)
        if (reason := violation_reason(path)) is not None
    ]
    if violations:
        for path, reason in violations:
            print(f"error: {path}: {reason}", file=sys.stderr)
        return 1

    print("Validated tracked public-source hygiene.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
