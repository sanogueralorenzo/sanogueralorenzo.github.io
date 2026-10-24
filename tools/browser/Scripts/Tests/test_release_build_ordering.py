"""Sparkle upgrades remain ordered when users move between release feeds."""

from __future__ import annotations

import pathlib
import subprocess
import tempfile
import unittest


class ReleaseBuildOrderingTests(unittest.TestCase):
    def test_development_outranks_final_experimental_and_both_products(self) -> None:
        script = pathlib.Path(__file__).resolve().parents[1] / "next-release-build-number.py"
        with tempfile.TemporaryDirectory() as directory:
            repository = pathlib.Path(directory)
            subprocess.run(["git", "init", "--quiet", directory], check=True)
            for filename, build in (("appcast.xml", 1070), ("appcast-development.xml", 1080),
                                    ("appcast-experimental.xml", 1100), ("appcast-experimental-webkit.xml", 1101)):
                (repository / filename).write_text(
                    '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
                    f'<channel><item><sparkle:version>{build}</sparkle:version></item></channel></rss>')
            subprocess.run(["git", "-C", directory, "add", "."], check=True)
            subprocess.run(["git", "-C", directory, "-c", "user.name=Crest Test",
                            "-c", "user.email=test@example.invalid", "commit", "--quiet", "-m", "Feeds"], check=True)
            result = subprocess.run(["python3", str(script), "--git-ref", "HEAD", "--minimum", "1090"],
                                    cwd=directory, check=True, capture_output=True, text=True)
            self.assertEqual(result.stdout.strip(), "1102")
            result = subprocess.run(["python3", str(script), "--git-ref", "HEAD", "--minimum", "1200"],
                                    cwd=directory, check=True, capture_output=True, text=True)
            self.assertEqual(result.stdout.strip(), "1200")
