#!/usr/bin/env python3
"""Install Crest's dedicated GitHub Actions runner in its managed build workspace."""
import argparse
import json
from pathlib import Path
import platform
import socket
import subprocess

from chromium_fork import REPO, RUNNER_WORK, download, run, sha256, validate_workspace


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, default=Path.home() / "Dev/CrestChromium")
    parser.add_argument("--repository", default="pauljoda/Crest")
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        parser.error("The Chromium runner requires an Apple Silicon Mac")
    root = validate_workspace(args.workspace, REPO)
    runner = root / "runner"
    if (runner / ".runner").exists():
        parser.error(f"A runner is already configured at {runner}; inspect it before reconfiguring")
    release = json.loads(run("gh", "api", "repos/actions/runner/releases/latest", capture=True))
    assets = [a for a in release["assets"] if a["name"].startswith("actions-runner-osx-arm64-") and a["name"].endswith(".tar.gz")]
    if len(assets) != 1 or not assets[0].get("digest", "").startswith("sha256:"):
        parser.error("GitHub did not return one checksum-pinned macOS ARM64 runner")
    asset = assets[0]
    archive = root / "downloads" / asset["name"]
    download(asset["browser_download_url"], archive)
    if sha256(archive) != asset["digest"].removeprefix("sha256:"):
        parser.error("GitHub runner checksum verification failed")
    runner.mkdir(parents=True, exist_ok=True)
    run("tar", "-xzf", archive, "-C", runner)
    registration = json.loads(run("gh", "api", "--method", "POST",
                                  f"repos/{args.repository}/actions/runners/registration-token", capture=True))
    # Do not print the registration token or store it in a command transcript.
    subprocess.run([str(runner / "config.sh"), "--unattended", "--url", f"https://github.com/{args.repository}",
                    "--token", registration["token"], "--name", f"crest-chromium-{socket.gethostname().split('.')[0]}",
                    "--labels", "crest-chromium", "--work", str(root / RUNNER_WORK)], cwd=runner, check=True)
    (runner / ".path").write_text(f"{root / 'tools/bin'}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    run(runner / "svc.sh", "install", cwd=runner)
    run(runner / "svc.sh", "start", cwd=runner)
    archive.unlink()
    print(f"Runner installed in {runner}. Signing remains on the release runner.")


if __name__ == "__main__":
    main()
