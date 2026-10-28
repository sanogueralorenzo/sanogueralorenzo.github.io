#!/usr/bin/env python3
"""Regression coverage for the public-source hygiene gate."""

from __future__ import annotations

import importlib.util
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
