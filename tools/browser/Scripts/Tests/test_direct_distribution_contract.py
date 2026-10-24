#!/usr/bin/env python3
"""Regression coverage for Crest's direct macOS release signing path."""

from __future__ import annotations

import pathlib
import plistlib
import importlib.util
import unittest

REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
EXPORT_OPTIONS = REPOSITORY_ROOT / "Config" / "DeveloperIDExportOptions.plist"
RELEASE_WORKFLOW = REPOSITORY_ROOT / ".github" / "workflows" / "release.yml"
PACKAGING_SPEC = importlib.util.spec_from_file_location(
    "package_chromium_host", REPOSITORY_ROOT / "Scripts/control-plane/package-chromium-host.py")
PACKAGING = importlib.util.module_from_spec(PACKAGING_SPEC)
PACKAGING_SPEC.loader.exec_module(PACKAGING)

class DirectDistributionContractTests(unittest.TestCase):

    def test_updates_require_the_newest_os_needed_by_the_engine_or_native_ui(self) -> None:
        for engine, native_ui, expected in (("13.0", "26.1", "26.1"), ("27.0", "26.1", "27.0"),
                                            ("10.9", "10.15.1", "10.15.1")):
            with self.subTest(engine=engine, native_ui=native_ui):
                self.assertEqual(PACKAGING.minimum_system_version(
                    {"LSMinimumSystemVersion": engine}, {"LSMinimumSystemVersion": native_ui}), expected)
        with self.assertRaises(KeyError):
            PACKAGING.minimum_system_version({"LSMinimumSystemVersion": "13.0"}, {})
        with self.assertRaises(ValueError):
            PACKAGING.minimum_system_version({"LSMinimumSystemVersion": "13.0"},
                                             {"LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)"})


    def test_release_note_cursor_advances_atomically_with_the_signed_appcast(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("release_note_marker:", workflow)
        self.assertIn('release_note_state_filename="release-note-publication.json"', workflow)
        self.assertIn('--previous-entry "$RELEASE_NOTE_MARKER"', workflow)
        self.assertIn("release_note_publication.py advance", workflow)
        self.assertIn(
            'git -C "$updates_checkout" add "$appcast_filename" "$webkit_appcast_filename" README.md '
            '"$release_note_state_filename"',
            workflow,
        )
        self.assertEqual(workflow.count("release_note_publication.py advance"), 1)
        self.assertLess(
            workflow.index("release_note_publication.py advance"),
            workflow.index('git -C "$updates_checkout" push origin HEAD:updates'),
        )


    def test_export_uses_the_named_developer_id_profile(self) -> None:
        with EXPORT_OPTIONS.open("rb") as stream:
            options = plistlib.load(stream)

        self.assertEqual(options["method"], "developer-id")
        self.assertEqual(options["signingStyle"], "manual")
        self.assertEqual(options["signingCertificate"], "Developer ID Application")
        self.assertEqual(options["teamID"], "3U2R97HLXF")
        self.assertEqual(
            options["provisioningProfiles"],
            {"com.pauldavis.crest": "Crest Developer ID"},
        )

    def test_release_workflow_preserves_production_entitlements(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        for required in (
            "DEVELOPER_ID_PROVISIONING_PROFILE_BASE64",
            'CODE_SIGN_STYLE=Manual',
            'CODE_SIGN_IDENTITY="Developer ID Application"',
            'CREST_PROVISIONING_PROFILE_SPECIFIER="Crest Developer ID"',
            "com.apple.application-identifier",
            "com.apple.developer.aps-environment",
            "com.apple.developer.icloud-container-identifiers:0",
            "keychain-access-groups:0",
            "diskutil image create from",
            '--volumeName "$volume"',
            "--format ULFO",
        ):
            with self.subTest(required=required):
                self.assertIn(required, workflow)

        archive = workflow.split("xcodebuild archive", 1)[1].split("xcodebuild -exportArchive", 1)[0]
        self.assertNotIn("CODE_SIGNING_ALLOWED=NO", archive)
        self.assertIn('--distribution', workflow)
        self.assertIn('codesign --verify --deep --strict --verbose=2 "$chromium_app"', workflow)
        self.assertNotIn("CODE_SIGN_STYLE=Automatic", workflow)
        self.assertNotIn("hdiutil create", workflow)

if __name__ == "__main__":
    unittest.main()
