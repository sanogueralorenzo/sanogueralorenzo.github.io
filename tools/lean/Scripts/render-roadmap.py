#!/usr/bin/env python3
"""Render the managed section of Documentation/ROADMAP.md from GitHub issues."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any, Optional


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ROADMAP = REPOSITORY_ROOT / "Documentation" / "ROADMAP.md"
START_MARKER = "<!-- crest-roadmap-sync:start -->"
END_MARKER = "<!-- crest-roadmap-sync:end -->"
COMMIT_LINE = re.compile(r"^commits?:\s*(?P<commits>[0-9a-fA-F, ]+)$", re.MULTILINE)
VERSION = re.compile(r"^v?(?P<version>\d+(?:\.\d+){1,2})(?:\b|$)")


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render Crest's public roadmap from roadmap-labelled GitHub issues."
    )
    parser.add_argument("--repository", default="pauljoda/Crest")
    parser.add_argument("--input", type=Path, help="Read a saved JSON snapshot instead of GitHub.")
    parser.add_argument("--roadmap", type=Path, default=DEFAULT_ROADMAP)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write", action="store_true", help="Update the roadmap in place.")
    mode.add_argument("--check", action="store_true", help="Fail when the roadmap is stale.")
    return parser.parse_args()


def run_json(arguments: list[str]) -> Any:
    result = subprocess.run(
        arguments,
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"{' '.join(arguments)} failed: {detail}")
    return json.loads(result.stdout)


def load_snapshot(
    path: Optional[Path], repository: str
) -> dict[str, list[dict[str, Any]]]:
    if path is not None:
        with path.open(encoding="utf-8") as stream:
            snapshot = json.load(stream)
        return {
            "issues": list(snapshot.get("issues", [])),
            "milestones": list(snapshot.get("milestones", [])),
        }

    issues = run_json(
        [
            "gh",
            "issue",
            "list",
            "--repo",
            repository,
            "--state",
            "all",
            "--limit",
            "1000",
            "--label",
            "roadmap",
            "--json",
            "number,title,url,state,stateReason,labels,milestone,body,closedAt",
        ]
    )
    milestone_pages = run_json(
        [
            "gh",
            "api",
            "--paginate",
            "--slurp",
            f"repos/{repository}/milestones?state=all&per_page=100",
        ]
    )
    milestones = [milestone for page in milestone_pages for milestone in page]
    return {"issues": issues, "milestones": milestones}


def label_names(issue: dict[str, Any]) -> set[str]:
    return {
        label["name"] if isinstance(label, dict) else str(label)
        for label in issue.get("labels", [])
    }


def release_sort_key(title: str) -> tuple[int, tuple[int, ...], str]:
    match = VERSION.match(title)
    if match is None:
        return (1, (), title.casefold())
    parts = tuple(int(part) for part in match.group("version").split("."))
    return (0, parts, title.casefold())


def completion_commits(issue: dict[str, Any]) -> list[str]:
    match = COMMIT_LINE.search(issue.get("body") or "")
    if match is None:
        return []
    return [
        commit.strip().lower()
        for commit in match.group("commits").split(",")
        if commit.strip()
    ]


def issue_line(issue: dict[str, Any], repository: str) -> str:
    checked = "x" if issue.get("state") == "CLOSED" else " "
    line = f"- [{checked}] [{issue['title']}]({issue['url']})"
    commits = completion_commits(issue)
    if commits:
        links = ", ".join(
            f"[`{commit[:8]}`](https://github.com/{repository}/commit/{commit})"
            for commit in commits
        )
        line += f" — {links}"
    return line


def render_managed_section(
    snapshot: dict[str, list[dict[str, Any]]], repository: str
) -> str:
    open_milestones = {
        milestone["title"]: milestone
        for milestone in snapshot["milestones"]
        if milestone.get("state", "open").lower() == "open"
    }
    grouped: dict[str, list[dict[str, Any]]] = {}
    for issue in snapshot["issues"]:
        milestone = issue.get("milestone")
        if "roadmap" not in label_names(issue) or not milestone:
            continue
        title = milestone["title"]
        if title not in open_milestones:
            continue
        grouped.setdefault(title, []).append(issue)

    lines = [
        START_MARKER,
        "## Active releases",
        "",
        "Release milestones are shown from earliest to latest. The project board holds",
        "the live status for each issue.",
    ]
    if not grouped:
        lines.extend(["", "No release milestone is currently active."])

    for title in sorted(grouped, key=release_sort_key):
        milestone = open_milestones[title]
        milestone_number = milestone.get("number")
        heading = title
        if milestone_number is not None:
            heading = (
                f"[{title}](https://github.com/{repository}/milestone/{milestone_number})"
            )
        lines.extend(["", f"### {heading}"])

        issues = sorted(grouped[title], key=lambda issue: int(issue["number"]))
        open_issues = [issue for issue in issues if issue.get("state") != "CLOSED"]
        completed_issues = [
            issue
            for issue in issues
            if issue.get("state") == "CLOSED"
            and issue.get("stateReason") != "NOT_PLANNED"
        ]
        canceled_issues = [
            issue
            for issue in issues
            if issue.get("state") == "CLOSED"
            and issue.get("stateReason") == "NOT_PLANNED"
        ]

        if open_issues:
            lines.extend(["", "#### Planned and in progress", ""])
            lines.extend(issue_line(issue, repository) for issue in open_issues)
        if completed_issues:
            lines.extend(["", "#### Completed", ""])
            lines.extend(issue_line(issue, repository) for issue in completed_issues)
        if canceled_issues:
            lines.extend(["", "#### Not planned", ""])
            lines.extend(issue_line(issue, repository) for issue in canceled_issues)

    lines.extend(["", END_MARKER])
    return "\n".join(lines)


def replace_managed_section(document: str, managed_section: str) -> str:
    if document.count(START_MARKER) != 1 or document.count(END_MARKER) != 1:
        raise ValueError("Roadmap must contain exactly one managed marker pair.")
    prefix, remainder = document.split(START_MARKER, 1)
    _, suffix = remainder.split(END_MARKER, 1)
    return f"{prefix}{managed_section}{suffix}"


def main() -> int:
    arguments = parse_arguments()
    try:
        snapshot = load_snapshot(arguments.input, arguments.repository)
        current = arguments.roadmap.read_text(encoding="utf-8")
        managed = render_managed_section(snapshot, arguments.repository)
        rendered = replace_managed_section(current, managed)
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    if arguments.check:
        if rendered != current:
            print("error: Documentation/ROADMAP.md is out of date", file=sys.stderr)
            return 1
        print("Validated the generated roadmap section.")
        return 0

    if arguments.write:
        if rendered != current:
            arguments.roadmap.write_text(rendered, encoding="utf-8")
            print(f"Updated {arguments.roadmap}.")
        else:
            print(f"No changes to {arguments.roadmap}.")
        return 0

    sys.stdout.write(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
