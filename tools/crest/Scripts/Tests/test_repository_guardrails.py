#!/usr/bin/env python3
"""Behavioral coverage for Crest's repository-lock guardrails."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
ARCHITECTURE_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-architecture.py"
FORMAT_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-swift-format.sh"

def load_architecture_module():
    spec = importlib.util.spec_from_file_location(
        "crest_architecture_guard", ARCHITECTURE_SCRIPT
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load Scripts/check-architecture.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class ArchitectureGuardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.guard = load_architecture_module()

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.fixture_root = Path(self.temporary_directory.name)
        for source_root in ("CrestShared", "CrestMac", "CrestMobile"):
            (self.fixture_root / source_root).mkdir()
        self.config_path = self.fixture_root / "guardrails.json"
        self.write_config()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_config(
        self,
        *,
        excluded_paths: list[dict[str, str]] | None = None,
        import_exemptions: list[dict[str, str]] | None = None,
        xcode_exemptions: list[dict[str, str]] | None = None,
    ) -> None:
        self.config_path.write_text(
            json.dumps(
                {
                    "excludedPathPrefixes": excluded_paths or [],
                    "importExemptions": import_exemptions or [],
                    "xcode27PatternExemptions": xcode_exemptions or [],
                }
            )
        )

    def write_source(self, relative_path: str, source: str) -> None:
        destination = self.fixture_root / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(source)

    def violations(self):
        config = self.guard.load_configuration(self.config_path)
        return self.guard.scan_repository(self.fixture_root, config)

    def violation_rules(self) -> set[str]:
        return {violation.rule for violation in self.violations()}

    def test_domain_and_application_reject_outer_layer_frameworks(self) -> None:
        self.write_source(
            "CrestShared/Domain/BadDomain.swift",
            "import SwiftUI\nstruct BadDomain {}\n",
        )
        self.write_source(
            "CrestShared/Application/BadApplication.swift",
            "import WebKit\nstruct BadApplication {}\n",
        )

        self.assertEqual(
            self.violation_rules(),
            {"layer-import"},
        )

    def test_xcode_27_state_and_builder_hazards_are_rejected(self) -> None:
        self.write_source(
            "CrestShared/Features/Compatibility.swift",
            """import SwiftUI
struct Compatibility: View {
    let title: String
    @State private var counter = 0

    init(title: String) {
        self.counter = 42
        self.title = title
    }

    var body: some View {
        Text(title)
            .overlay(Color.blue.opacity(0.7))
    }
}

extension Compatibility where Body == TupleView<(Text, Text)> {}
""",
        )

        self.assertEqual(
            self.violation_rules(),
            {
                "xcode27-builder-modifier",
                "xcode27-state-default-init",
                "xcode27-state-initialization-order",
                "xcode27-tuple-view-constraint",
            },
        )

class SwiftFormatGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.fixture_root = Path(self.temporary_directory.name)
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
        (self.fixture_root / ".swift-format").write_text('{"version": 1}\n')
        (self.fixture_root / "Changed.swift").write_text("struct Changed {}\n")
        subprocess.run(
            ["git", "add", "."], cwd=self.fixture_root, check=True
        )
        subprocess.run(
            ["git", "commit", "-qm", "fixture"],
            cwd=self.fixture_root,
            check=True,
        )
        (self.fixture_root / "Changed.swift").write_text("struct Changed{ }\n")
        (self.fixture_root / "Untracked.swift").write_text("struct New{ }\n")
        (self.fixture_root / "notes.txt").write_text("not Swift\n")

        self.argument_log = self.fixture_root / "formatter-arguments.txt"
        self.fake_formatter = self.fixture_root / "swift-format"
        self.fake_formatter.write_text(
            "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$CREST_TEST_ARGUMENT_LOG\"\n"
        )
        self.fake_formatter.chmod(0o755)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

if __name__ == "__main__":
    unittest.main()
