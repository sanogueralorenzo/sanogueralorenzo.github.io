#!/usr/bin/env python3
"""Run release preflight against a local Git repository and recorded GitHub data."""

from __future__ import annotations

import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
WORKFLOW = REPOSITORY_ROOT / ".github/workflows/release.yml"


def workflow_script(step_name: str) -> str:
    step = WORKFLOW.read_text().split(f"      - name: {step_name}\n", 1)[1]
    match = re.search(r"(?m)^        run: \|\n((?: {10}.*\n|\n)+)", step)
    if match is None:
        raise AssertionError(f"No shell script in {step_name}")
    return textwrap.dedent(match.group(1))


class ReleasePreflightTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)
        self.repository = self.root / "repository"
        self.repository.mkdir()
        self.git("init", "--initial-branch=main")
        self.git("config", "user.name", "Crest Tests")
        self.git("config", "user.email", "crest-tests@example.invalid")
        self.git("remote", "add", "origin", str(self.repository))
        (self.repository / "Config").mkdir()
        (self.repository / "Config/Version.xcconfig").write_text("MARKETING_VERSION = 0.5.25\n")
        (self.repository / "Documentation").mkdir()
        shutil.copyfile(
            REPOSITORY_ROOT / "Documentation/ReleaseNotes.json",
            self.repository / "Documentation/ReleaseNotes.json",
        )
        (self.repository / "Scripts").symlink_to(REPOSITORY_ROOT / "Scripts")
        self.git("add", "Config", "Documentation")
        self.git("commit", "-m", "Previous build")
        self.previous_commit = self.git("rev-parse", "HEAD")
        self.git("tag", "v0.5.24")
        (self.repository / "change.txt").write_text("New change\n")
        self.git("add", "change.txt")
        self.git("commit", "-m", "Current build")
        self.current_commit = self.git("rev-parse", "HEAD")
        self.git("branch", "updates")

        bin_directory = self.root / "bin"
        bin_directory.mkdir()
        self.github_log = self.root / "github.log"
        github = bin_directory / "gh"
        github.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "arguments = sys.argv[1:]\n"
            "with open(os.environ['TEST_GITHUB_LOG'], 'a') as log:\n"
            "    log.write(json.dumps(arguments) + '\\n')\n"
            "if arguments[0] == 'api' and 'releases?per_page=100' in arguments[-1]:\n"
            "    prereleases = [{'tag_name': 'nightly-old', 'draft': False, 'prerelease': True}] * 100\n"
            "    stable = [{'tag_name': 'v0.5.24', 'draft': False, 'prerelease': False}]\n"
            "    print(json.dumps([prereleases, stable] if '--slurp' in arguments else prereleases))\n"
            "    sys.exit(0)\n"
            "sys.exit('Unexpected GitHub request: ' + repr(arguments))\n"
        )
        github.chmod(0o755)
        self.environment = os.environ | {
            "PATH": f"{bin_directory}{os.pathsep}{os.environ['PATH']}",
            "GH_TOKEN": "",
            "GITHUB_TOKEN": "",
            "GITHUB_EVENT_NAME": "schedule",
            "GITHUB_REF_TYPE": "branch",
            "GITHUB_REF_NAME": "main",
            "GITHUB_REPOSITORY": "pauljoda/Crest",
            "GITHUB_SHA": self.current_commit,
            "GITHUB_RUN_NUMBER": "61",
            "GITHUB_RUN_ATTEMPT": "1",
            "GITHUB_OUTPUT": str(self.root / "output"),
            "GITHUB_STEP_SUMMARY": str(self.root / "summary"),
            "RUNNER_TEMP": str(self.root),
            "REQUESTED_CHANNEL": "",
            "TEST_GITHUB_LOG": str(self.github_log),
        }

    def git(self, *arguments: str) -> str:
        return subprocess.run(
            ["git", "-C", str(self.repository), *arguments],
            check=True, capture_output=True, text=True,
        ).stdout.strip()

    def publish_appcast(self, channel: str, commit: str, tag: str, build: int = 1060) -> None:
        self.git("checkout", "updates")
        filename = "appcast-development.xml" if channel == "development" else "appcast.xml"
        (self.repository / filename).write_text(
            '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            f"<channel><item><sparkle:channel>{channel}</sparkle:channel>"
            f"<sparkle:version>{build}</sparkle:version>"
            f'<enclosure url="https://github.com/pauljoda/Crest/releases/download/{tag}/'
            f'Installer-Crest-0.5.25-{channel}-2026-09-03-{commit[:7]}-arm64.dmg" />'
            "</item></channel></rss>"
        )
        self.git("add", filename)
        self.git("commit", "-m", "Publish appcast")
        self.git("checkout", "main")

    def preflight(self, **environment: str) -> tuple[subprocess.CompletedProcess[str], dict[str, str]]:
        output_path = self.root / "output"
        output_path.unlink(missing_ok=True)
        result = subprocess.run(
            ["bash", "-c", workflow_script("Resolve release identity and previous publication")],
            cwd=self.repository, env=self.environment | environment,
            capture_output=True, text=True, timeout=20,
        )
        outputs = dict(line.split("=", 1) for line in output_path.read_text().splitlines()) if output_path.exists() else {}
        return result, outputs

    def test_stable_dispatch_branch_push_and_mismatched_tags_are_rejected(self) -> None:
        scenarios = (
            {"GITHUB_EVENT_NAME": "workflow_dispatch", "REQUESTED_CHANNEL": "stable", "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v0.5.25"},
            {"GITHUB_EVENT_NAME": "push"},
            {"GITHUB_EVENT_NAME": "push", "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v0.5.24"},
        )
        for environment in scenarios:
            with self.subTest(environment=environment):
                result, outputs = self.preflight(**environment)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(outputs, {})

    def test_interrupted_publications_cannot_reuse_another_runs_release_tag(self) -> None:
        self.publish_appcast("nightly", self.previous_commit, "nightly-build", build=1070)
        tags = set()
        for run in ("61", "62"):
            result, outputs = self.preflight(GITHUB_RUN_NUMBER=run)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(outputs["build_number"], "1071")
            tags.add(outputs["release_tag"])
        self.assertEqual(len(tags), 2)


if __name__ == "__main__":
    unittest.main()
