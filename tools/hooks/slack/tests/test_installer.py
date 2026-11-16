import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class InstallerTests(unittest.TestCase):
    def test_fresh_install_and_update_use_managed_source_without_touching_home(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            git = bin_dir / "git"
            git.write_text(
                "#!"
                + sys.executable
                + """
import json,sys
from pathlib import Path
args=sys.argv[1:]
root=Path(__file__).parent.parent
with (root/'git-calls').open('a') as out: out.write(json.dumps(args)+'\\n')
if args[0]=='clone':
 source=Path(args[-1]);(source/'.git').mkdir(parents=True)
 bridge=source/'tools/hooks/cli.py';bridge.parent.mkdir(parents=True)
 bridge.write_text('import sys\\nargs=sys.argv[1:]; assert args[:2]==["install","--home"]; assert __import__("pathlib").Path(args[2]).resolve()==__import__("pathlib").Path(__file__).resolve().parents[3]; assert args[3:]==["--workspace","/fixture/project"]\\nprint("INSTALL_OK")\\n')
"""
            )
            git.chmod(0o700)
            cargo = bin_dir / "cargo"
            cargo.write_text("#!/bin/sh\nexit 0\n")
            cargo.chmod(0o700)
            env = {
                **os.environ,
                "PATH": str(bin_dir) + os.pathsep + os.environ.get("PATH", ""),
                "BROWSER_HOOKS_HOME": str(root / "install"),
            }
            installer = Path(__file__).resolve().parents[2] / "install.sh"
            for _ in range(2):
                result = subprocess.run(
                    ["sh", str(installer), "--workspace", "/fixture/project"],
                    capture_output=True,
                    text=True,
                    env=env,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("INSTALL_OK", result.stdout)
            calls = [
                json.loads(line)
                for line in (root / "git-calls").read_text().splitlines()
            ]
            self.assertEqual(sum(c[0] == "clone" for c in calls), 1)
            self.assertTrue(any("pull" in c and "--ff-only" in c for c in calls))
            self.assertTrue(
                any("sparse-checkout" in c and "tools/hooks" in c for c in calls)
            )


if __name__ == "__main__":
    unittest.main()
