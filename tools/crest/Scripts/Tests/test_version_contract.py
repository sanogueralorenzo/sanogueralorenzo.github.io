#!/usr/bin/env python3
"""Regression coverage for Crest's semantic-version contract."""

from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECK_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-version.sh"
SET_SCRIPT = REPOSITORY_ROOT / "Scripts" / "set-version.sh"


class VersionContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.fixture_root = pathlib.Path(self.temporary_directory.name)

        for relative_path in (
            "Config/Version.xcconfig",
            "CrestMac/Configuration/Crest-Info.plist",
            "CrestMobile/Configuration/CrestMobile-Info.plist",
            "Documentation/ReleaseNotes.json",
            "project.yml",
        ):
            source = REPOSITORY_ROOT / relative_path
            destination = self.fixture_root / relative_path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

        (self.fixture_root / "Crest.xcodeproj").mkdir()
        self.environment = os.environ | {
            "CREST_VERSION_REPOSITORY_ROOT": str(self.fixture_root),
        }
        self.current_version = self.current_marketing_version()
        major, minor, patch = (
            int(part) for part in self.current_version.split(".")
        )
        self.next_patch_version = f"{major}.{minor}.{patch + 1}"
        self.two_fix_version = f"{major}.{minor}.{patch + 2}"
        self.next_release_line = f"{major}.{minor + 1}.0"

        subprocess.run(["git", "init", "-q"], cwd=self.fixture_root, check=True)
        subprocess.run(
            ["git", "config", "user.email", "crest-tests@example.com"],
            cwd=self.fixture_root,
            check=True,
        )
        subprocess.run(
            ["git", "config", "user.name", "Crest Tests"],
            cwd=self.fixture_root,
            check=True,
        )
        subprocess.run(["git", "add", "."], cwd=self.fixture_root, check=True)
        subprocess.run(
            ["git", "commit", "-qm", "fixture"],
            cwd=self.fixture_root,
            check=True,
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def run_check(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(CHECK_SCRIPT), *arguments],
            cwd=self.fixture_root,
            env=self.environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def current_marketing_version(self) -> str:
        contents = (
            self.fixture_root / "Config" / "Version.xcconfig"
        ).read_text()
        return contents.split("=", maxsplit=1)[1].strip()

    def write_version(self, version: str) -> None:
        (self.fixture_root / "Config" / "Version.xcconfig").write_text(
            f"MARKETING_VERSION = {version}\n"
        )

    def stage_version(self) -> None:
        subprocess.run(
            ["git", "add", "Config/Version.xcconfig"],
            cwd=self.fixture_root,
            check=True,
        )

    def test_repository_contract_passes_static_validation(self) -> None:
        result = subprocess.run(
            [str(CHECK_SCRIPT), "--static"],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(self.current_version, result.stdout)

    def test_static_check_rejects_malformed_semver(self) -> None:
        version_file = self.fixture_root / "Config" / "Version.xcconfig"

        for malformed in (
            "0.3",
            "01.3.0",
            "0.03.0",
            "0.3.00",
            "0.3.0-beta.1",
            "0.3.0+build.1",
        ):
            with self.subTest(version=malformed):
                version_file.write_text(f"MARKETING_VERSION = {malformed}\n")
                result = self.run_check("--static")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("strict X.Y.Z SemVer", result.stderr)

    def test_static_check_rejects_literal_plist_versions(self) -> None:
        plist = self.fixture_root / "CrestMac" / "Configuration" / "Crest-Info.plist"
        contents = plist.read_text().replace("$(MARKETING_VERSION)", "0.3.0")
        plist.write_text(contents)

        result = self.run_check("--static")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must substitute $(MARKETING_VERSION)", result.stderr)

    def test_static_check_rejects_configuration_drift(self) -> None:
        project = self.fixture_root / "project.yml"
        contents = project.read_text().replace(
            "  Release: Config/Version.xcconfig",
            "  Release: Config/ReleaseVersion.xcconfig",
            1,
        )
        project.write_text(contents)

        result = self.run_check("--static")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Release must inherit Config/Version.xcconfig", result.stderr)

    def test_fix_commit_check_rejects_a_missing_staged_patch_bump(self) -> None:
        self.write_version(self.next_patch_version)

        result = self.run_check("--fix-commit")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stage Config/Version.xcconfig", result.stderr)

    def test_fix_commit_check_rejects_a_missing_staged_release_note(self) -> None:
        self.write_version(self.next_patch_version)
        self.stage_version()

        result = self.run_check("--fix-commit")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stage at least one new release-note entry", result.stderr)

    def test_fix_commit_check_rejects_a_new_release_line(self) -> None:
        self.write_version(self.next_release_line)
        self.stage_version()

        result = self.run_check("--fix-commit")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("patch version", result.stderr)


if __name__ == "__main__":
    unittest.main()
