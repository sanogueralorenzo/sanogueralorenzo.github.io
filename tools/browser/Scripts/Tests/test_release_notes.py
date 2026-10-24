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

    def test_catalog_diff_survives_rewritten_commit_history(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            baseline_entries = {
                "existing-change": {
                    "category": "fixed",
                    "message": "Keep existing behavior reliable",
                }
            }
            self.write_catalog(repository, baseline_entries)
            base_commit = self.commit(repository, "Repository baseline")

            published_entries = baseline_entries | {
                "published-change": {
                    "category": "new",
                    "message": "Open a second page beside the first",
                }
            }
            self.write_catalog(repository, published_entries)
            previous_commit = self.commit(repository, "feat: old-history split view")

            self.run_git(repository, "checkout", "-b", "rewritten", base_commit)
            self.write_catalog(repository, published_entries)
            self.commit(repository, "feat: rewritten split view")

            current_entries = published_entries | {
                "current-change": {
                    "category": "fixed",
                    "message": "Keep dragged tabs attached to the pointer",
                }
            }
            self.write_catalog(repository, current_entries)
            current_commit = self.commit(repository, "fix: current drag behavior")

            result = self.generate_notes(repository, current_commit, previous_commit)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("- Keep dragged tabs attached to the pointer", result.stdout)
            self.assertNotIn("Open a second page beside the first", result.stdout)
            self.assertNotIn("old-history split view", result.stdout)

    def test_legacy_fallback_ignores_patch_equivalent_rewritten_commits(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            base_commit = self.commit(repository, "Repository baseline")
            previous_commit = self.commit(repository, "fix: keep tabs visible")

            self.run_git(repository, "checkout", "-b", "rewritten", base_commit)
            self.commit(
                repository,
                "fix: keep tabs visible",
                "Equivalent change recreated by a history rewrite.",
            )
            current_commit = self.commit(repository, "feat: add vertical tabs")

            result = self.generate_notes(repository, current_commit, previous_commit)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("- Add vertical tabs", result.stdout)
            self.assertNotIn("Keep tabs visible", result.stdout)

    def test_legacy_fallback_prefers_an_exact_tree_equivalent_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            base_commit = self.commit(repository, "Repository baseline")
            self.commit(repository, "fix: first published change")
            previous_commit = self.commit(repository, "fix: second published change")
            published_tree = self.run_git(repository, "show", "HEAD:tracked.txt")

            self.run_git(repository, "checkout", "-b", "rewritten", base_commit)
            (repository / "tracked.txt").write_text(f"{published_tree}\n")
            self.run_git(repository, "add", "tracked.txt")
            self.run_git(repository, "commit", "-m", "Combine published changes")
            rewritten_boundary = self.run_git(repository, "rev-parse", "HEAD")
            self.assertEqual(
                self.run_git(repository, "rev-parse", f"{previous_commit}^{{tree}}"),
                self.run_git(repository, "rev-parse", f"{rewritten_boundary}^{{tree}}"),
            )
            current_commit = self.commit(repository, "feat: add tab groups")

            result = self.generate_notes(repository, current_commit, previous_commit)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("- Add tab groups", result.stdout)
            self.assertNotIn("Combine published changes", result.stdout)

    def test_notes_group_user_facing_changes_and_hide_internal_commit_noise(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            previous_commit = self.commit(repository, "Initial release", "Already published.")
            first_commit = self.commit(
                repository,
                "feat(browser): add split view",
                "Implementation detail that does not belong in release notes.",
            )
            second_commit = self.commit(repository, "perf: speed up tab switching")
            third_commit = self.commit(repository, "Polish the onboarding flow (#42)")
            self.commit(repository, "Fix disappearing tabs")
            self.commit(repository, "chore(release): prepare 0.4.0")
            self.commit(repository, "fix(ci): restore hosted validation")
            current_commit = self.commit(
                repository,
                "fix: restore toolbar spacing (APP-249)",
            )

            result = subprocess.run(
                [
                    "python3",
                    str(RELEASE_NOTES_SCRIPT),
                    "--repository-root",
                    str(repository),
                    "--repository",
                    "pauljoda/Crest",
                    "--channel",
                    "development",
                    "--current-ref",
                    current_commit,
                    "--previous-ref",
                    previous_commit,
                    "--asset-name",
                    "Installer-Crest-0.4.0-development-test-arm64.dmg",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            notes = result.stdout
            self.assertIn("## Highlights", notes)
            self.assertIn("### New", notes)
            self.assertIn("- Add split view", notes)
            self.assertIn("### Improved", notes)
            self.assertIn("- Speed up tab switching", notes)
            self.assertIn("- Polish the onboarding flow", notes)
            self.assertIn("### Fixed", notes)
            self.assertIn("- Fix disappearing tabs", notes)
            self.assertIn("- Restore toolbar spacing", notes)
            self.assertLess(notes.index("### Fixed"), notes.index("Fix disappearing tabs"))
            self.assertIn(
                "[Download the installer]"
                "(https://github.com/pauljoda/Crest/releases/download/development/"
                "Installer-Crest-0.4.0-development-test-arm64.dmg)",
                notes,
            )
            self.assertIn("Development builds contain the newest changes", notes)
            self.assertNotIn("Initial release", notes)
            self.assertNotIn("Implementation detail", notes)
            self.assertNotIn("prepare 0.4.0", notes)
            self.assertNotIn("hosted validation", notes)
            self.assertNotIn("feat(browser)", notes)
            self.assertNotIn("(#42)", notes)
            self.assertNotIn("(APP-249)", notes)
            self.assertIn(
                "[View all changes]"
                f"(https://github.com/pauljoda/Crest/compare/{previous_commit}...{current_commit})",
                notes,
            )
            self.assertLess(notes.index("Add split view"), notes.index("Speed up tab switching"))
            self.assertLess(notes.index("Speed up tab switching"), notes.index("Polish the onboarding flow"))
            self.assertNotIn(first_commit[:7], notes)
            self.assertNotIn(second_commit[:7], notes)
            self.assertNotIn(third_commit[:7], notes)

    def test_first_channel_build_describes_only_the_current_commit(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            self.commit(repository, "Repository history")
            current_commit = self.commit(repository, "First nightly build", "The current change.")

            result = subprocess.run(
                [
                    "python3",
                    str(RELEASE_NOTES_SCRIPT),
                    "--repository-root",
                    str(repository),
                    "--repository",
                    "pauljoda/Crest",
                    "--channel",
                    "nightly",
                    "--current-ref",
                    current_commit,
                    "--asset-name",
                    "Installer-Crest-0.4.0-nightly-test-arm64.dmg",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            notes = result.stdout
            self.assertNotIn("Repository history", notes)
            self.assertIn("- First nightly build", notes)
            self.assertNotIn("The current change.", notes)
            self.assertIn(
                f"[View source](https://github.com/pauljoda/Crest/commit/{current_commit})",
                notes,
            )

    def test_notes_limit_highlights_and_link_to_the_complete_comparison(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            previous_commit = self.commit(repository, "Initial release")
            for index in range(14):
                current_commit = self.commit(repository, f"fix: restore behavior {index}")

            result = subprocess.run(
                [
                    "python3",
                    str(RELEASE_NOTES_SCRIPT),
                    "--repository-root",
                    str(repository),
                    "--repository",
                    "pauljoda/Crest",
                    "--channel",
                    "nightly",
                    "--current-ref",
                    current_commit,
                    "--previous-ref",
                    previous_commit,
                    "--asset-name",
                    "Installer-Crest-0.4.0-nightly-test-arm64.dmg",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            notes = result.stdout
            self.assertNotIn("- Restore behavior 0\n", notes)
            self.assertNotIn("- Restore behavior 1\n", notes)
            self.assertIn("- Restore behavior 2\n", notes)
            self.assertIn("- Restore behavior 13\n", notes)
            self.assertEqual(notes.count("- Restore behavior"), 12)
            self.assertIn("Showing the 12 most recent highlights from 14 user-facing changes.", notes)
            self.assertIn(
                "[View all changes]"
                f"(https://github.com/pauljoda/Crest/compare/{previous_commit}...{current_commit})",
                notes,
            )

    def test_notes_omit_merge_commits_but_keep_their_user_facing_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            self.run_git(repository, "init", "--initial-branch=main")
            self.run_git(repository, "config", "user.name", "Crest Tests")
            self.run_git(repository, "config", "user.email", "tests@crestbrowser.com")

            previous_commit = self.commit(repository, "Initial release")
            self.run_git(repository, "checkout", "-b", "feature")
            self.run_git(repository, "commit", "--allow-empty", "-m", "feat: add profiles")
            self.run_git(repository, "checkout", "main")
            self.commit(repository, "fix: restore navigation")
            self.run_git(repository, "merge", "--no-ff", "feature", "-m", "Merge feature")
            current_commit = self.run_git(repository, "rev-parse", "HEAD")

            result = subprocess.run(
                [
                    "python3",
                    str(RELEASE_NOTES_SCRIPT),
                    "--repository-root",
                    str(repository),
                    "--repository",
                    "pauljoda/Crest",
                    "--channel",
                    "development",
                    "--current-ref",
                    current_commit,
                    "--previous-ref",
                    previous_commit,
                    "--asset-name",
                    "Installer-Crest-development-test-arm64.dmg",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            notes = result.stdout
            self.assertIn("- Add profiles", notes)
            self.assertIn("- Restore navigation", notes)
            self.assertNotIn("Merge feature", notes)


if __name__ == "__main__":
    unittest.main()
