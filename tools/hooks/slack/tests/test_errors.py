from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "agents"))
from errors import classify


class ErrorTests(unittest.TestCase):
    def test_classifier_only_returns_fixed_diagnostics(self):
        private = "fixture-private-secret"
        for text, code in [
            ("OAuth token has expired", "auth_required"),
            ("429 rate limit", "usage_limit"),
            ("approval required", "permission_required"),
            ("session not found", "session_invalid"),
            ("thread already has an active writer", "session_busy"),
            ("unexpected failure", "command_failed"),
        ]:
            error = classify(text + " " + private, "Claude")
            self.assertEqual(error.code, code)
            self.assertNotIn(private, str(error))


if __name__ == "__main__":
    unittest.main()
