"""Profile migration preserves data and resumes after an interrupted launch."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ProfileAdoptionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(prefix="crest-adoption-tests-")
        cls.addClassCleanup(cls.build.cleanup)
        source = Path(cls.build.name) / "adopt.cc"
        source.write_text('''#include <iostream>
#include "CrestEngines/Chromium/Overlay/chrome/app/crest_user_data_dir.h"
int main(int argc, char** argv) {
  if (argc != 2) return 64;
  std::cout << crest::AdoptProductUserDataDirectory(argv[1]);
}
''')
        cls.executable = Path(cls.build.name) / "adopt"
        subprocess.run([shutil.which("clang++") or "c++", "-std=c++20", "-I", str(ROOT),
                        str(source), "-o", str(cls.executable)], check=True, capture_output=True)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="crest-adoption-home-")
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name)
        self.previous = self.home / "Library/Application Support/Chromium"
        self.preferred = self.home / "Library/Application Support/Crest/Chromium"
        self.previous.mkdir(parents=True)
        self.preferred.mkdir(parents=True)

    def profile(self, root, name, contents="saved cookies"):
        profile = root / name
        profile.mkdir()
        (profile / "Cookies").write_text(contents)
        return profile

    def adopt(self, succeeds=True):
        result = subprocess.run([str(self.executable), str(self.home)], capture_output=True, text=True)
        if succeeds:
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, str(self.preferred))
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def test_empty_destination_from_interrupted_launch_does_not_hide_existing_profiles(self):
        self.profile(self.previous, "Crest-A")
        self.profile(self.previous, "Crest-B")
        self.profile(self.previous, "Default", "other browser")
        self.adopt()
        record = (self.preferred / "Crest Adoption").read_text()
        self.assertEqual(record.splitlines(), [str(self.previous), "Crest-A", "Crest-B"])
        self.assertEqual((self.preferred / "Crest-A/Cookies").read_text(), "saved cookies")
        self.assertEqual((self.preferred / "Crest-B/Cookies").read_text(), "saved cookies")
        self.assertEqual((self.previous / "Default/Cookies").read_text(), "other browser")
        self.adopt()
        self.assertEqual((self.preferred / "Crest Adoption").read_text(), record)

    def test_partial_move_resumes_from_the_durable_record(self):
        self.profile(self.preferred, "Crest-A", "already moved")
        self.profile(self.previous, "Crest-B", "waiting")
        (self.preferred / "Crest Adoption").write_text(f"{self.previous}\nCrest-A\nCrest-B\n")
        self.adopt()
        self.assertEqual((self.preferred / "Crest-A/Cookies").read_text(), "already moved")
        self.assertEqual((self.preferred / "Crest-B/Cookies").read_text(), "waiting")

    def test_legacy_interruption_after_all_moves_still_records_metadata_repair(self):
        self.profile(self.preferred, "Crest-A")
        self.adopt()
        self.assertEqual((self.preferred / "Crest Adoption").read_text().splitlines(),
                         [str(self.previous), "Crest-A"])

    def test_conflicting_profiles_stop_without_overwriting_either_copy(self):
        self.profile(self.previous, "Crest-A", "old")
        self.profile(self.preferred, "Crest-A", "new")
        self.adopt(succeeds=False)
        self.assertEqual((self.previous / "Crest-A/Cookies").read_text(), "old")
        self.assertEqual((self.preferred / "Crest-A/Cookies").read_text(), "new")
        self.assertTrue((self.preferred / "Crest Adoption").exists())

    def test_incomplete_or_invalid_record_preserves_the_profiles(self):
        self.profile(self.previous, "Crest-A")
        for contents in (f"{self.previous}\nCrest-A", f"{self.previous}\nCrest-../../escape\n"):
            with self.subTest(record=contents):
                (self.preferred / "Crest Adoption").write_text(contents)
                self.adopt(succeeds=False)
                self.assertEqual((self.previous / "Crest-A/Cookies").read_text(), "saved cookies")
                self.assertFalse((self.preferred / "Crest-A").exists())

    def test_completed_migration_does_not_readopt_later_unrelated_profiles(self):
        (self.preferred / "Crest Adoption Complete").write_text(f"{self.previous}\n")
        self.profile(self.previous, "Crest-Later", "another installation")
        self.adopt()
        self.assertTrue((self.previous / "Crest-Later").exists())
        self.assertFalse((self.preferred / "Crest-Later").exists())


if __name__ == "__main__":
    unittest.main()
