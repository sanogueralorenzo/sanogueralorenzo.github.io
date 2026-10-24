#!/usr/bin/env python3
"""Say which Apple app builds a change can affect, so CI skips the others.

Prints `mac=true|false` and `ios=true|false` lines for `$GITHUB_OUTPUT`. A
change that touches only documentation builds neither app, and one confined to
one app's own folders leaves the other alone. The version, the release-note
catalog and the generated project ride along with most app changes without
deciding which app they reach; a change of nothing else builds both. A release
source, a manual run, and a change whose files cannot be listed build both.
"""

from __future__ import annotations

from dataclasses import dataclass
import os
import subprocess
import sys


@dataclass(frozen=True)
class Area:
    """Paths of the repository that only some builds read."""

    name: str
    folders: tuple[str, ...] = ()
    files: tuple[str, ...] = ()
    root_suffixes: tuple[str, ...] = ()
    excluded: tuple[str, ...] = ()

    def holds(self, path: str) -> bool:
        if path in self.excluded:
            return False
        if path in self.files or path.startswith(self.folders):
            return True
        return "/" not in path and path.endswith(self.root_suffixes)


# What no app build reads. Both apps bundle the release-note catalog, so it
# is not documentation here.
DOCUMENTATION = Area(
    name="documentation",
    folders=("Website/", "HelpCenter/", "Marketing/", "Documentation/", ".github/ISSUE_TEMPLATE/"),
    root_suffixes=(".md", "LICENSE", "NOTICE"),
    excluded=("Documentation/ReleaseNotes.json",),
)
# What both apps read but no change to it can break one app alone. CI
# regenerates the project from project.yml before it builds.
SHARED_METADATA = Area(
    name="shared metadata",
    folders=("Crest.xcodeproj/",),
    files=("Config/Version.xcconfig", "Documentation/ReleaseNotes.json"),
)
MAC_ONLY = Area(
    name="macOS only",
    folders=("CrestMac/", "CrestEngines/", "CrestDockTilePlugin/", "CrestTests/", "CrestAgents/", "CrestAgentHelper/"))
IOS_ONLY = Area(name="iOS only", folders=("CrestMobile/", "CrestMobileTests/"))


def git(*arguments: str) -> list[str] | None:
    """The lines git prints, or None when it fails."""
    result = subprocess.run(["git", *arguments], capture_output=True, text=True)
    return result.stdout.splitlines() if result.returncode == 0 else None


def changed_paths() -> list[str] | None:
    """The files the change touches, or None when every build should run."""
    if os.environ.get("SOURCE_SHA"):
        return None
    event = os.environ.get("EVENT_NAME", "")
    if event == "pull_request":
        # The checkout is GitHub's merge commit; its first parent is the base.
        return git("diff", "--name-only", "HEAD^1", "HEAD")
    if event == "push":
        # The checkout holds the commit before a one-commit push; an earlier
        # one is fetched.
        before = os.environ.get("BEFORE_SHA", "")
        if not before.strip("0"):
            return None
        if git("cat-file", "-e", f"{before}^{{commit}}") is None \
                and git("fetch", "--quiet", "--depth=1", "origin", before) is None:
            return None
        return git("diff", "--name-only", before, "HEAD")
    return None


def main() -> int:
    paths = changed_paths()
    if paths is None:
        mac = ios = True
        print("Building both apps: no file list for this run.", file=sys.stderr)
    else:
        built = [path for path in paths if not DOCUMENTATION.holds(path)]
        deciding = [path for path in built if not SHARED_METADATA.holds(path)]
        if built and not deciding:
            mac = ios = True
        else:
            mac = any(not IOS_ONLY.holds(path) for path in deciding)
            ios = any(not MAC_ONLY.holds(path) for path in deciding)
        print(f"{len(paths)} changed files, {len(built)} outside documentation.", file=sys.stderr)
    print(f"mac={str(mac).lower()}")
    print(f"ios={str(ios).lower()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
