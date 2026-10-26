#!/usr/bin/env python3
"""Behavioral coverage for Crest's commit-based release notes."""

from __future__ import annotations

import json
import pathlib
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
RELEASE_NOTES_SCRIPT = REPOSITORY_ROOT / "Scripts" / "generate-release-notes.py"


class ReleaseNotesTests(unittest.TestCase):
    def run_git(self, repository: pathlib.Path, *arguments: str) -> str:
        result = subprocess.run(
            ["git", "-C", str(repository), *arguments],
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()

    def commit(
        self,
        repository: pathlib.Path,
        subject: str,
        body: str | None = None,
    ) -> str:
        tracked_file = repository / "tracked.txt"
        previous = tracked_file.read_text() if tracked_file.exists() else ""
        tracked_file.write_text(f"{previous}{subject}\n")
        self.run_git(repository, "add", tracked_file.name)
        arguments = ["commit", "-m", subject]
        if body is not None:
            arguments.extend(["-m", body])
        self.run_git(repository, *arguments)
        return self.run_git(repository, "rev-parse", "HEAD")

    def write_catalog(
        self,
        repository: pathlib.Path,
        entries: dict[str, dict[str, str]],
    ) -> None:
        catalog = repository / "Documentation" / "ReleaseNotes.json"
        catalog.parent.mkdir(parents=True, exist_ok=True)
        catalog.write_text(
            json.dumps(
                {"schemaVersion": 1, "entries": entries},
                indent=2,
            )
            + "\n"
        )
        self.run_git(repository, "add", str(catalog.relative_to(repository)))

    def generate_notes(
        self,
        repository: pathlib.Path,
        current_commit: str,
        previous_commit: str | None = None,
        previous_entry: str | None = None,
        channel: str = "nightly",
        release_tag: str | None = None,
    ) -> subprocess.CompletedProcess[str]:
        arguments = [
            "python3",
            str(RELEASE_NOTES_SCRIPT),
            "--repository-root",
            str(repository),
            "--repository",
            "pauljoda/Crest",
            "--channel",
            channel,
            "--current-ref",
            current_commit,
            "--asset-name",
            "Installer-Crest-nightly-test-arm64.dmg",
        ]
        if previous_commit is not None:
            arguments.extend(["--previous-ref", previous_commit])
        if previous_entry is not None:
            arguments.extend(["--previous-entry", previous_entry])
        if release_tag is not None:
            arguments.extend(["--release-tag", release_tag])
        return subprocess.run(
            arguments,
            check=False,
            capture_output=True,
            text=True,
        )

    def test_channel_links_and_installer_use_the_distinct_release_tag(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "crest-tests@example.invalid")
            previous = self.commit(repository, "Initial build")
            current = self.commit(repository, "fix: Keep release history")
            for channel in ("stable", "nightly", "development"):
                with self.subTest(channel=channel):
                    tag = "v0.5.25" if channel == "stable" else f"{channel}-0.5.25-2026-09-03-1061-r61.1"
                    result = self.generate_notes(
                        repository, current, previous,
                        channel=channel, release_tag=tag,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(f"/releases/download/{tag}/Installer-", result.stdout)
                    query = (
                        "prerelease%3Afalse" if channel == "stable"
                        else f"prerelease%3Atrue+%22{channel.title()}+builds%22"
                    )
                    self.assertIn(
                        f"[Browse {channel.title()} releases](https://github.com/pauljoda/Crest/releases?q={query})",
                        result.stdout,
                    )

    def test_catalog_controls_public_categories_and_copy(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            entries = {
                "existing-change": {
                    "category": "fixed",
                    "message": "Keep existing behavior reliable",
                }
            }
            self.write_catalog(repository, entries)
            previous_commit = self.commit(repository, "fix: misleading old subject")

            entries |= {
                "profiles": {
                    "category": "new",
                    "message": "Create separate browsing profiles for different contexts",
                },
                "tab-switching": {
                    "category": "improved",
                    "message": "Switch between large tab collections more smoothly",
                },
                "navigation": {
                    "category": "fixed",
                    "message": "Keep navigation controls in sync with the active page",
                },
                "release-plumbing": {
                    "category": "internal",
                    "message": "Adopt the structured release-note catalog",
                },
            }
            self.write_catalog(repository, entries)
            current_commit = self.commit(repository, "chore: wording that must stay private")

            result = self.generate_notes(repository, current_commit, previous_commit)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("### New", result.stdout)
            self.assertIn("- Create separate browsing profiles for different contexts", result.stdout)
            self.assertIn("### Improved", result.stdout)
            self.assertIn("- Switch between large tab collections more smoothly", result.stdout)
            self.assertIn("### Fixed", result.stdout)
            self.assertIn("- Keep navigation controls in sync with the active page", result.stdout)
            self.assertNotIn("Keep existing behavior reliable", result.stdout)
            self.assertNotIn("structured release-note catalog", result.stdout)
            self.assertNotIn("wording that must stay private", result.stdout)

    def test_catalog_cursor_selects_entries_after_its_channel_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            self.write_catalog(
                repository,
                {
                    "stable-boundary": {
                        "category": "internal",
                        "message": "Record the stable publication boundary",
                    },
                    "development-change": {
                        "category": "new",
                        "message": "Open links in a compact preview",
                    },
                    "nightly-boundary": {
                        "category": "internal",
                        "message": "Record the nightly publication boundary",
                    },
                    "current-fix": {
                        "category": "fixed",
                        "message": "Keep pinned tabs safe during iCloud Sync",
                    },
                },
            )
            current_commit = self.commit(repository, "fix: private implementation subject")

            nightly = self.generate_notes(
                repository,
                current_commit,
                previous_entry="nightly-boundary",
            )
            stable = self.generate_notes(
                repository,
                current_commit,
                previous_entry="stable-boundary",
            )

            self.assertEqual(nightly.returncode, 0, nightly.stderr)
            self.assertNotIn("Open links in a compact preview", nightly.stdout)
            self.assertIn("Keep pinned tabs safe during iCloud Sync", nightly.stdout)
            self.assertEqual(stable.returncode, 0, stable.stderr)
            self.assertIn("Open links in a compact preview", stable.stdout)
            self.assertIn("Keep pinned tabs safe during iCloud Sync", stable.stdout)


if __name__ == "__main__":
    unittest.main()
