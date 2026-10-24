#!/usr/bin/env python3
"""Focused behavioral coverage for Crest's source-organization guard."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
GUARD_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-vertical-structure.py"

def load_guard_module():
    spec = importlib.util.spec_from_file_location(
        "crest_vertical_structure_guard", GUARD_SCRIPT
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load Scripts/check-vertical-structure.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class VerticalFeatureContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.guard = load_guard_module()

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repository_root = Path(self.temporary_directory.name)
        for source_root in ("CrestShared", "CrestMac", "CrestMobile"):
            (self.repository_root / source_root).mkdir()
        self.configuration_path = self.repository_root / "debt.json"
        self.write_configuration([])

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def write_source(self, relative_path: str, source: str) -> None:
        destination = self.repository_root / relative_path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(source)

    def write_configuration(self, violations: list[dict[str, str]]) -> None:
        rules: dict[str, dict[str, object]] = {}
        for violation in violations:
            rule_configuration = rules.setdefault(
                violation["rule"],
                {
                    "reason": violation["reason"],
                    "violations": [],
                },
            )
            rule_configuration["violations"].append(
                [violation["path"], violation["subject"]]
            )
        self.configuration_path.write_text(
            json.dumps({"rules": rules}, indent=2, sort_keys=True) + "\n"
        )

    def violation_keys(self) -> set[tuple[str, str, str]]:
        return {
            (violation.rule, violation.path, violation.subject)
            for violation in self.guard.scan_repository(self.repository_root)
        }


    def test_existing_previews_reject_live_and_nondeterministic_state(self) -> None:
        self.write_source(
            "CrestShared/Features/Sample/SampleView.swift",
            """import SwiftUI
struct SampleView: View {
    @AppStorage("sample") private var sample = false
    var body: some View { Text("Sample") }
}
#Preview {
    let identifier = UUID()
    _ = UserDefaults.standard
    return SampleView()
}
""",
        )

        keys = self.violation_keys()
        relative_path = "CrestShared/Features/Sample/SampleView.swift"
        self.assertIn(
            ("preview-live-dependency", relative_path, "UserDefaults"),
            keys,
        )
        self.assertIn(
            ("preview-live-app-storage", relative_path, "@AppStorage"),
            keys,
        )
        self.assertIn(
            ("preview-nondeterministic-fixture", relative_path, "UUID()"),
            keys,
        )

    def test_debt_ledger_rejects_stale_entries(self) -> None:
        relative_path = "CrestShared/Domain/Owner+Equatable.swift"
        self.write_source(
            relative_path,
            "struct Helper {}\nextension Owner: Equatable {}\n",
        )
        self.write_configuration(
            [
                {
                    "rule": "extension-file-primary-type",
                    "path": relative_path,
                    "subject": "Helper",
                    "reason": "Existing migration debt.",
                }
            ]
        )
        configured_debt = self.guard.load_debt_configuration(
            self.configuration_path
        )

        matching_audit = self.guard.audit_repository(
            self.repository_root, configured_debt
        )
        self.assertEqual(matching_audit.unexpected, [])
        self.assertEqual(matching_audit.stale, [])

        self.write_source(relative_path, "extension Owner: Equatable {}\n")
        stale_audit = self.guard.audit_repository(
            self.repository_root, configured_debt
        )
        self.assertEqual(stale_audit.unexpected, [])
        self.assertEqual(
            [entry.key for entry in stale_audit.stale],
            [("extension-file-primary-type", relative_path, "Helper")],
        )

if __name__ == "__main__":
    unittest.main()
