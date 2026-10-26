#!/usr/bin/env python3
"""Generate user-facing release notes from Crest's explicit change catalog."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import pathlib
import re
import subprocess
import urllib.parse

from release_note_catalog import (
    CATALOG_PATH,
    CatalogValidationError,
    ReleaseNoteEntry,
    parse_catalog,
)


CHANNEL_DESCRIPTIONS = {
    "stable": "Stable releases are signed, notarized, and ready for everyday use.",
    "nightly": (
        "Nightly builds contain the newest changes and may be less reliable "
        "than stable releases."
    ),
    "development": (
        "Development builds contain the newest changes and may be less reliable "
        "than stable releases."
    ),
}

CATEGORY_HEADINGS = (
    ("new", "New"),
    ("improved", "Improved"),
    ("fixed", "Fixed"),
)

CATEGORY_BY_COMMIT_TYPE = {
    "feat": "new",
    "fix": "fixed",
    "perf": "improved",
    "revert": "fixed",
}

INTERNAL_COMMIT_TYPES = {
    "build",
    "chore",
    "ci",
    "docs",
    "refactor",
    "style",
    "test",
}

INTERNAL_COMMIT_SCOPES = {
    "build",
    "ci",
    "distribution",
    "docs",
    "release",
    "test",
    "tooling",
    "workflow",
}

CONVENTIONAL_SUBJECT = re.compile(
    r"^(?P<type>[A-Za-z]+)(?:\((?P<scope>[^)]+)\))?!?:\s*(?P<description>.+)$"
)
ISSUE_REFERENCE_SUFFIX = re.compile(
    r"\s+\((?:#\d+|[A-Z][A-Z0-9]+-\d+)\)$"
)
NEW_CHANGE_VERBS = {
    "add",
    "added",
    "adds",
    "enable",
    "enabled",
    "enables",
    "introduce",
    "introduced",
    "introduces",
    "support",
    "supported",
    "supports",
}
FIXED_CHANGE_VERBS = {
    "correct",
    "corrected",
    "corrects",
    "fix",
    "fixed",
    "fixes",
    "prevent",
    "prevented",
    "prevents",
    "restore",
    "restored",
    "restores",
    "resolve",
    "resolved",
    "resolves",
}
MAX_HIGHLIGHTS = 12


@dataclass(frozen=True)
class ReleaseNoteChange:
    category: str
    description: str


def git(repository_root: pathlib.Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repository_root), *arguments],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def git_result(
    repository_root: pathlib.Path,
    *arguments: str,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repository_root), *arguments],
        check=False,
        capture_output=True,
        text=True,
    )


def is_ancestor(
    repository_root: pathlib.Path,
    possible_ancestor: str,
    current_commit: str,
) -> bool:
    result = git_result(
        repository_root,
        "merge-base",
        "--is-ancestor",
        possible_ancestor,
        current_commit,
    )
    if result.returncode in (0, 1):
        return result.returncode == 0
    result.check_returncode()
    return False


def tree_equivalent_ancestor(
    repository_root: pathlib.Path,
    previous_commit: str,
    current_commit: str,
) -> str | None:
    previous_tree = git(repository_root, "rev-parse", f"{previous_commit}^{{tree}}")
    history = git(
        repository_root,
        "log",
        "--format=%H%x09%T",
        current_commit,
    ).splitlines()
    for history_entry in history:
        commit, tree = history_entry.split("\t", maxsplit=1)
        if tree == previous_tree:
            return commit
    return None


def commit_range(
    repository_root: pathlib.Path,
    current_ref: str,
    previous_ref: str | None,
) -> tuple[str, list[str]]:
    current_commit = git(repository_root, "rev-parse", f"{current_ref}^{{commit}}")
    if previous_ref is None:
        return current_commit, [current_commit]

    previous_commit = git(repository_root, "rev-parse", f"{previous_ref}^{{commit}}")
    if is_ancestor(repository_root, previous_commit, current_commit):
        revision_range = f"{previous_commit}..{current_commit}"
        range_options: tuple[str, ...] = ()
    elif equivalent_commit := tree_equivalent_ancestor(
        repository_root,
        previous_commit,
        current_commit,
    ):
        revision_range = f"{equivalent_commit}..{current_commit}"
        range_options = ()
    else:
        revision_range = f"{previous_commit}...{current_commit}"
        range_options = ("--right-only", "--cherry-pick")

    commits = git(
        repository_root,
        "rev-list",
        "--reverse",
        "--no-merges",
        *range_options,
        revision_range,
    ).splitlines()
    return current_commit, commits


def catalog_at_ref(
    repository_root: pathlib.Path,
    reference: str,
) -> dict[str, ReleaseNoteEntry] | None:
    result = git_result(repository_root, "show", f"{reference}:{CATALOG_PATH}")
    if result.returncode != 0:
        return None
    return parse_catalog(result.stdout, f"{reference}:{CATALOG_PATH}")


def catalog_changes(
    repository_root: pathlib.Path,
    current_commit: str,
    previous_ref: str | None,
    previous_entry: str | None,
) -> list[ReleaseNoteChange] | None:
    current_entries = catalog_at_ref(repository_root, current_commit)
    if current_entries is None:
        return None

    if previous_entry is not None:
        if previous_entry not in current_entries:
            raise CatalogValidationError(
                f"release-note cursor '{previous_entry}' is not in the current catalog"
            )
        include_entry = False
        changes: list[ReleaseNoteChange] = []
        for identifier, entry in current_entries.items():
            if identifier == previous_entry:
                include_entry = True
                continue
            if include_entry and entry.category != "internal":
                changes.append(ReleaseNoteChange(entry.category, entry.message))
        return changes

    if previous_ref is None:
        previous_entries = catalog_at_ref(repository_root, f"{current_commit}^")
    else:
        previous_entries = catalog_at_ref(repository_root, previous_ref)
    if previous_entries is None:
        return None

    return [
        ReleaseNoteChange(entry.category, entry.message)
        for identifier, entry in current_entries.items()
        if identifier not in previous_entries and entry.category != "internal"
    ]


def release_note_change(subject: str) -> ReleaseNoteChange | None:
    match = CONVENTIONAL_SUBJECT.match(subject)
    if match is None:
        description = polished_subject(subject)
        return ReleaseNoteChange(inferred_category(description), description)

    commit_type = match.group("type").lower()
    scope = (match.group("scope") or "").lower()
    if commit_type in INTERNAL_COMMIT_TYPES or scope in INTERNAL_COMMIT_SCOPES:
        return None

    category = CATEGORY_BY_COMMIT_TYPE.get(commit_type, "improved")
    return ReleaseNoteChange(category, polished_subject(match.group("description")))


def inferred_category(description: str) -> str:
    leading_verb = description.partition(" ")[0].lower()
    if leading_verb in NEW_CHANGE_VERBS:
        return "new"
    if leading_verb in FIXED_CHANGE_VERBS:
        return "fixed"
    return "improved"


def polished_subject(subject: str) -> str:
    description = ISSUE_REFERENCE_SUFFIX.sub("", subject).strip()
    if not description:
        return description
    return description[0].upper() + description[1:]


def release_note_sections(changes: list[ReleaseNoteChange]) -> list[str]:
    if not changes:
        return ["### Maintenance", "", "- Reliability and internal improvements.", ""]

    lines: list[str] = []
    for category, heading in CATEGORY_HEADINGS:
        descriptions = [change.description for change in changes if change.category == category]
        if not descriptions:
            continue
        lines.extend([f"### {heading}", ""])
        lines.extend(f"- {description}" for description in descriptions)
        lines.append("")
    return lines


def release_notes(
    repository_root: pathlib.Path,
    repository: str,
    server_url: str,
    channel: str,
    release_tag: str,
    current_ref: str,
    previous_ref: str | None,
    previous_entry: str | None,
    asset_name: str,
) -> str:
    current_commit = git(repository_root, "rev-parse", f"{current_ref}^{{commit}}")
    changes = catalog_changes(
        repository_root,
        current_commit,
        previous_ref,
        previous_entry,
    )
    if changes is None:
        _, commits = commit_range(repository_root, current_commit, previous_ref)
        changes = [
            change
            for commit in commits
            if (
                change := release_note_change(
                    git(repository_root, "show", "-s", "--format=%s", commit)
                )
            )
        ]

    repository_url = f"{server_url.rstrip('/')}/{repository}"
    channel_query = (
        "prerelease:false" if channel == "stable"
        else f'prerelease:true "{channel.title()} builds"'
    )
    channel_url = f"{repository_url}/releases?{urllib.parse.urlencode({'q': channel_query})}"
    download_url = (
        f"{repository_url}/releases/download/"
        f"{urllib.parse.quote(release_tag, safe='.-_')}/"
        f"{urllib.parse.quote(asset_name, safe='.-_')}"
    )
    visible_changes = changes[-MAX_HIGHLIGHTS:]
    has_linear_history = previous_ref is not None and is_ancestor(
        repository_root,
        git(repository_root, "rev-parse", f"{previous_ref}^{{commit}}"),
        current_commit,
    )
    if has_linear_history:
        details_url = f"{repository_url}/compare/{previous_ref}...{current_commit}"
        details_label = "View all changes"
    else:
        details_url = f"{repository_url}/commit/{current_commit}"
        details_label = "View source"

    lines = ["## Highlights", ""]
    if len(changes) > len(visible_changes):
        lines.extend(
            [
                (
                    f"Showing the {len(visible_changes)} most recent highlights "
                    f"from {len(changes)} user-facing changes."
                ),
                "",
            ]
        )
    lines.extend(release_note_sections(visible_changes))
    lines.extend(
        [
            "---",
            "",
            CHANNEL_DESCRIPTIONS[channel],
            "",
            f"[{details_label}]({details_url}) · [Download the installer]({download_url})",
            "",
            f"[Browse {channel.title()} releases]({channel_url})",
            "",
        ]
    )

    return "\n".join(lines).rstrip() + "\n"


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument("--repository", required=True)
    parser.add_argument("--server-url", default="https://github.com")
    parser.add_argument("--channel", choices=CHANNEL_DESCRIPTIONS, required=True)
    parser.add_argument("--release-tag")
    parser.add_argument("--current-ref", required=True)
    parser.add_argument("--previous-ref")
    parser.add_argument("--previous-entry")
    parser.add_argument("--asset-name", required=True)
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    print(
        release_notes(
            repository_root=arguments.repository_root,
            repository=arguments.repository,
            server_url=arguments.server_url,
            channel=arguments.channel,
            release_tag=arguments.release_tag or arguments.channel,
            current_ref=arguments.current_ref,
            previous_ref=arguments.previous_ref,
            previous_entry=arguments.previous_entry,
            asset_name=arguments.asset_name,
        ),
        end="",
    )


if __name__ == "__main__":
    main()
