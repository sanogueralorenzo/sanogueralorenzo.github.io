#!/usr/bin/env python3
"""Behavioral coverage for per-channel release-note publication cursors."""

from __future__ import annotations

import importlib.util
import json
import pathlib
import tempfile
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]


def load_script_module(name: str, filename: str):
    path = REPOSITORY_ROOT / "Scripts" / filename
    specification = importlib.util.spec_from_file_location(name, path)
    if specification is None or specification.loader is None:
        raise RuntimeError(f"Unable to load {path}")
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


class ReleaseNotePublicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.publication = load_script_module(
            "release_note_publication",
            "release_note_publication.py",
        )

    def catalog_contents(self) -> str:
        return json.dumps(
            {
                "schemaVersion": 2,
                "publicationBaselines": {
                    "stable": "stable-boundary",
                    "development": "development-boundary",
                    "nightly": "nightly-boundary",
                },
                "entries": {
                    "stable-boundary": {
                        "category": "internal",
                        "message": "Record the stable publication boundary",
                    },
                    "development-boundary": {
                        "category": "internal",
                        "message": "Record the development publication boundary",
                    },
                    "nightly-boundary": {
                        "category": "internal",
                        "message": "Record the nightly publication boundary",
                    },
                    "new-change": {
                        "category": "new",
                        "message": "Open a second page beside the first",
                    },
                },
            }
        )

    def test_missing_state_uses_backfilled_catalog_baselines(self) -> None:
        catalog = self.publication.parse_catalog_document(
            self.catalog_contents(),
            "catalog",
        )

        state = self.publication.effective_publication_state(catalog, None)

        self.assertEqual(state.channels["stable"], "stable-boundary")
        self.assertEqual(state.channels["development"], "development-boundary")
        self.assertEqual(state.channels["nightly"], "nightly-boundary")

    def test_each_channel_advances_without_consuming_the_other_channels(self) -> None:
        catalog = self.publication.parse_catalog_document(
            self.catalog_contents(),
            "catalog",
        )
        state = self.publication.effective_publication_state(catalog, None)

        advanced = self.publication.advance_channel(catalog, state, "nightly")

        self.assertEqual(advanced.channels["nightly"], "new-change")
        self.assertEqual(advanced.channels["development"], "development-boundary")
        self.assertEqual(advanced.channels["stable"], "stable-boundary")

    def test_state_rejects_a_cursor_that_is_not_in_the_catalog(self) -> None:
        catalog = self.publication.parse_catalog_document(
            self.catalog_contents(),
            "catalog",
        )
        invalid_state = json.dumps(
            {
                "schemaVersion": 1,
                "channels": {
                    "stable": "stable-boundary",
                    "development": "missing-entry",
                    "nightly": "nightly-boundary",
                },
            }
        )

        with self.assertRaisesRegex(ValueError, "missing-entry"):
            self.publication.parse_publication_state(
                invalid_state,
                "state",
                catalog,
            )

    def test_state_file_is_written_only_when_advance_is_requested(self) -> None:
        catalog = self.publication.parse_catalog_document(
            self.catalog_contents(),
            "catalog",
        )
        state = self.publication.effective_publication_state(catalog, None)

        with tempfile.TemporaryDirectory() as temporary_directory:
            output = pathlib.Path(temporary_directory) / "publication.json"
            self.assertFalse(output.exists())

            advanced = self.publication.advance_channel(catalog, state, "nightly")
            self.publication.write_publication_state(output, advanced)

            written = json.loads(output.read_text())
            self.assertEqual(written["channels"]["nightly"], "new-change")
            self.assertEqual(
                written["channels"]["development"],
                "development-boundary",
            )


if __name__ == "__main__":
    unittest.main()
