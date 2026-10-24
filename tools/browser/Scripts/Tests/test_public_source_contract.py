#!/usr/bin/env python3
"""Regression coverage for the public-source hygiene gate."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CHECK_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-public-source.py"


def load_check_module():
    spec = importlib.util.spec_from_file_location("crest_public_source", CHECK_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load Scripts/check-public-source.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PublicSourceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.check = load_check_module()

    def test_current_tracked_tree_is_public_source_clean(self) -> None:
        result = subprocess.run(
            [str(CHECK_SCRIPT)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_private_working_files_and_signing_material_are_rejected(self) -> None:
        for path in (
            "CrestMac/AGENTS.md",
            "CLAUDE.local.md",
            ".claude/settings.json",
            ".claude/skills/other-skill/SKILL.md",
            ".agents/skills/other-skill/SKILL.md",
            ".codex/config.toml",
            ".codex-build/runtime.log",
            "nested/.codex-review/Crest.app/Contents/Info.plist",
            ".crest-review/session/screenshot.png",
            ".cursor/rules.md",
            ".github/copilot-instructions.md",
            "Config/AuthKey_TEST.p8",
            "Config/DeveloperID.p12",
            "Config/Crest.provisionprofile",
            "Project.xcodeproj/xcuserdata/user.xcuserdatad/state",
        ):
            with self.subTest(path=path):
                self.assertIsNotNone(self.check.violation_reason(path))

    def test_public_configuration_examples_remain_allowed(self) -> None:
        for path in (
            "AGENTS.md",
            ".agents/skills/crest-contribution/SKILL.md",
            ".agents/skills/crest-contribution/references/library-style.md",
            ".claude/skills/crest-contribution",
            ".env.example",
            "CrestMac/Infrastructure/WebKit/BrowserPlatformUserAgent.swift",
            "Documentation/Design.md",
        ):
            with self.subTest(path=path):
                self.assertIsNone(self.check.violation_reason(path))


if __name__ == "__main__":
    unittest.main()
