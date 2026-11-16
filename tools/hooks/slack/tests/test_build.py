import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from slack.build import build


class BuildTests(unittest.TestCase):
    def test_build_is_locked_private_and_atomically_replaces_the_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "app with spaces"
            binary = home / "bin/slack-bridge"
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b"old executable")
            cargo = root / "cargo"
            cargo.write_text(
                "#!"
                + sys.executable
                + """
import os,sys
from pathlib import Path
assert '--locked' in sys.argv and '--release' in sys.argv
binary=Path(os.environ['CARGO_TARGET_DIR'])/'release/slack-bridge'
binary.parent.mkdir(parents=True)
binary.write_bytes(b'new executable')
"""
            )
            cargo.chmod(0o700)
            with (
                binary.open("rb") as previous,
                patch.dict(os.environ, {"PATH": str(root)}),
            ):
                result = build(home, root / "checkout")
                self.assertEqual(previous.read(), b"old executable")
            self.assertEqual(result, binary)
            self.assertEqual(binary.read_bytes(), b"new executable")
            self.assertEqual(binary.stat().st_mode & 0o777, 0o700)
            self.assertTrue((home / "build/slack-build.log").exists())


if __name__ == "__main__":
    unittest.main()
