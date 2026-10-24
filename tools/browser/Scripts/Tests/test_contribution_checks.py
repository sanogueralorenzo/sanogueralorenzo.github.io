#!/usr/bin/env python3
"""Durable failure modes of the pull request contribution checks."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
CHECK_SCRIPT = REPOSITORY_ROOT / "Scripts" / "check-contribution.py"
TEMPLATE = REPOSITORY_ROOT / ".github" / "PULL_REQUEST_TEMPLATE.md"


def load_check_module():
    spec = importlib.util.spec_from_file_location("crest_contribution", CHECK_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load Scripts/check-contribution.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def commit(message: str, parents: int = 1) -> dict:
    return {
        "sha": "0123456789abcdef",
        "parents": [{"sha": "p"}] * parents,
        "commit": {"message": message},
    }


class ContributionCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.check = load_check_module()
        cls.template = TEMPLATE.read_text(encoding="utf-8")

    def test_template_carries_both_markers_unchecked(self) -> None:
        states = self.check.checkbox_states(self.template)
        self.assertEqual(
            states,
            {self.check.AI_USED_MARKER: False, self.check.SKILL_MARKER: False},
        )
        self.assertEqual(self.check.ai_declaration_problems(self.template), [])

    def test_ai_use_without_the_skill_is_rejected(self) -> None:
        body = self.template.replace(f"- [ ] {self.check.AI_USED_MARKER}", f"- [x] {self.check.AI_USED_MARKER}")
        self.assertEqual(len(self.check.ai_declaration_problems(body)), 1)

        body = body.replace("- [ ] I ran the `crest-contribution`", "- [x] I ran the `crest-contribution`")
        self.assertEqual(self.check.ai_declaration_problems(body), [])

    def test_missing_section_is_rejected(self) -> None:
        self.assertEqual(len(self.check.ai_declaration_problems("## What changed\n\nA fix.")), 1)

    def test_pull_requests_before_the_policy_are_exempt(self) -> None:
        self.assertTrue(self.check.opened_before_policy("2026-10-06T14:40:38Z"))
        self.assertFalse(self.check.opened_before_policy("2026-10-09T00:00:00Z"))

    def test_sign_off_is_required_except_for_merges(self) -> None:
        signed = commit("fix: a thing\n\nSigned-off-by: Person <person@example.com>")
        unsigned = commit("fix: a thing")
        empty_trailer = commit("fix: a thing\n\nSigned-off-by:")
        merge = commit("Merge branch 'main'", parents=2)

        self.assertEqual(self.check.sign_off_problems([signed, merge]), [])
        self.assertEqual(len(self.check.sign_off_problems([signed, unsigned, empty_trailer])), 2)

    def test_only_the_pull_request_author_can_exempt_a_pull_request(self) -> None:
        self.assertTrue(self.check.exempt_from_sign_off("dependabot[bot]", set()))
        self.assertTrue(self.check.exempt_from_sign_off("owner", {"owner"}))
        self.assertFalse(self.check.exempt_from_sign_off("person", {"owner"}))


if __name__ == "__main__":
    unittest.main()
