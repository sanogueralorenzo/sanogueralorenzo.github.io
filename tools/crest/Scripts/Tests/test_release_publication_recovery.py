#!/usr/bin/env python3
"""Behavioral coverage for interrupted GitHub Release publication recovery."""

from __future__ import annotations

import hashlib
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


class PublishedReleaseResolutionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.resolver = load_script_module(
            "resolve_published_release",
            "resolve-published-release.py",
        )

    def test_development_baseline_comes_from_the_latest_appcast_installer(self) -> None:
        appcast = """\
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <sparkle:channel>development</sparkle:channel>
      <enclosure url="https://github.com/pauljoda/Crest/releases/download/development/Installer-Crest-0.4.0-development-2026-08-17-3e67cd3-arm64.dmg" />
    </item>
    <item>
      <sparkle:channel>development</sparkle:channel>
      <enclosure url="https://github.com/pauljoda/Crest/releases/download/development/Crest-0.4.0-development-2026-08-17-0c2900b-arm64.dmg" />
    </item>
  </channel>
</rss>
"""

        commit = self.resolver.published_commit_prefix(appcast, "development")

        self.assertEqual(commit, "3e67cd3")


class FakeGitHub:
    def __init__(self, asset_name: str, asset_size: int, asset_digest: str) -> None:
        self.asset_name = asset_name
        self.asset_size = asset_size
        self.asset_digest = asset_digest
        self.assets: list[dict[str, object]] = []
        self.commands: list[tuple[str, ...]] = []
        self.delete_failures_remaining = 0
        self.upload_failures_remaining = 0
        self.next_asset_id = 100

    def run(self, arguments: list[str]) -> str:
        self.commands.append(tuple(arguments))
        if arguments[:2] == ["api", "repos/pauljoda/Crest/releases/tags/development"]:
            return json.dumps({"id": 42})
        if arguments[:3] == ["api", "--paginate", "--slurp"]:
            return json.dumps([self.assets])
        if arguments[:2] == ["api", "--method"]:
            asset_id = int(arguments[-1].rsplit("/", 1)[-1])
            self.assets = [asset for asset in self.assets if asset["id"] != asset_id]
            if self.delete_failures_remaining:
                self.delete_failures_remaining -= 1
                raise RuntimeError("HTTP 503")
            return ""
        if arguments[:2] == ["release", "upload"]:
            self.next_asset_id += 1
            state = "uploaded"
            digest: str | None = self.asset_digest
            if self.upload_failures_remaining:
                self.upload_failures_remaining -= 1
                state = "starter"
                digest = None
            self.assets.append(
                {
                    "id": self.next_asset_id,
                    "name": self.asset_name,
                    "state": state,
                    "size": self.asset_size,
                    "digest": digest,
                }
            )
            if state == "starter":
                raise RuntimeError("HTTP 503")
            return ""
        raise AssertionError(f"Unexpected gh command: {arguments}")


class ReleaseAssetRecoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.reconciler = load_script_module(
            "reconcile_release_assets",
            "reconcile-release-assets.py",
        )

    def make_asset(self, directory: pathlib.Path) -> tuple[pathlib.Path, FakeGitHub]:
        asset = directory / "Installer-Crest-0.4.0-development-test-arm64.dmg"
        asset.write_bytes(b"notarized crest installer")
        digest = f"sha256:{hashlib.sha256(asset.read_bytes()).hexdigest()}"
        github = FakeGitHub(asset.name, asset.stat().st_size, digest)
        return asset, github

    def test_starter_asset_is_deleted_before_the_installer_is_reuploaded(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            asset, github = self.make_asset(pathlib.Path(temporary_directory))
            github.assets.append(
                {
                    "id": 8,
                    "name": github.asset_name,
                    "state": "starter",
                    "size": github.asset_size,
                    "digest": None,
                }
            )

            self.reconciler.reconcile_asset(
                repository="pauljoda/Crest",
                release_tag="development",
                asset_path=asset,
                run_github=github.run,
                sleep=lambda _: None,
            )

            self.assertEqual(github.assets[0]["state"], "uploaded")
            self.assertEqual(github.assets[0]["digest"], github.asset_digest)
            self.assertTrue(
                any(command[:2] == ("api", "--method") for command in github.commands)
            )


if __name__ == "__main__":
    unittest.main()
