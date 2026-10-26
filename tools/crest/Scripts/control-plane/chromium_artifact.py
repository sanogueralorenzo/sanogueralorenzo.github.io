"""Require a complete published engine matching the full input key."""
import argparse
import json
import os
from pathlib import Path
import subprocess

import chromium_engine


def release_ready(release, key):
    if release is None or release.get("draft"):
        return False
    asset = chromium_engine.asset_name(key)
    names = {item["name"] for item in release.get("assets", [])
             if item.get("state") == "uploaded" and item.get("size", 0) > 0}
    if key not in (release.get("body") or "") or not {asset, f"{asset}.sha256"} <= names:
        raise ValueError("Published engine is incomplete or has a different full input key; refusing to replace it")
    return True


def published_release(repository, key):
    result = subprocess.run(["gh", "api", f"repos/{repository}/releases/tags/{chromium_engine.release_tag(key)}"],
                            capture_output=True, text=True)
    if result.returncode:
        if "(HTTP 404)" in result.stderr:
            return None
        raise RuntimeError(f"Cannot inspect the engine release: {result.stderr.strip()}")
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", "pauljoda/Crest"))
    parser.add_argument("--require", action="store_true")
    args = parser.parse_args()
    key = chromium_engine.engine_key(Path(__file__).resolve().parents[2])
    ready = release_ready(published_release(args.repository, key), key)
    tag = chromium_engine.release_tag(key)
    print(f"{tag}: {'published' if ready else 'build required'}")
    if output := os.environ.get("GITHUB_OUTPUT"):
        with Path(output).open("a") as stream:
            stream.write(f"ready={str(ready).lower()}\nengine_tag={tag}\n")
    if args.require and not ready:
        raise SystemExit("The required engine has not been published")


if __name__ == "__main__":
    main()
