#!/usr/bin/env python3
"""Idempotently publish a verified asset set to an existing GitHub Release."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
import time
from collections.abc import Callable, Sequence


GitHubCommand = Callable[[list[str]], str]
Sleep = Callable[[float], None]


def run_github_command(arguments: list[str]) -> str:
    result = subprocess.run(
        ["gh", *arguments],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return result.stdout


def local_digest(asset_path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with asset_path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return f"sha256:{digest.hexdigest()}"


def release_assets(
    repository: str,
    release_tag: str,
    run_github: GitHubCommand,
) -> list[dict[str, object]]:
    release = json.loads(
        run_github(["api", f"repos/{repository}/releases/tags/{release_tag}"])
    )
    pages = json.loads(
        run_github(
            [
                "api",
                "--paginate",
                "--slurp",
                f"repos/{repository}/releases/{release['id']}/assets?per_page=100",
            ]
        )
    )
    return [asset for page in pages for asset in page]


def is_uploaded_file(
    remote_asset: dict[str, object],
    asset_path: pathlib.Path,
    digest: str,
) -> bool:
    return (
        remote_asset.get("state") == "uploaded"
        and remote_asset.get("size") == asset_path.stat().st_size
        and remote_asset.get("digest") == digest
    )


def reconcile_asset(
    repository: str,
    release_tag: str,
    asset_path: pathlib.Path,
    run_github: GitHubCommand = run_github_command,
    sleep: Sleep = time.sleep,
    attempts: int = 6,
    initial_delay_seconds: float = 2,
) -> None:
    if attempts < 1:
        raise ValueError("attempts must be positive")
    if not asset_path.is_file():
        raise FileNotFoundError(asset_path)

    digest = local_digest(asset_path)
    delay = initial_delay_seconds
    last_error: Exception | None = None

    for attempt in range(1, attempts + 1):
        try:
            assets = release_assets(repository, release_tag, run_github)
            matches = [asset for asset in assets if asset.get("name") == asset_path.name]
            if len(matches) == 1 and is_uploaded_file(matches[0], asset_path, digest):
                return

            for remote_asset in matches:
                run_github(
                    [
                        "api",
                        "--method",
                        "DELETE",
                        f"repos/{repository}/releases/assets/{remote_asset['id']}",
                    ]
                )

            run_github(
                [
                    "release",
                    "upload",
                    release_tag,
                    str(asset_path),
                    "--repo",
                    repository,
                ]
            )
            uploaded_assets = release_assets(repository, release_tag, run_github)
            uploaded = [
                asset for asset in uploaded_assets if asset.get("name") == asset_path.name
            ]
            if len(uploaded) == 1 and is_uploaded_file(uploaded[0], asset_path, digest):
                return
            raise RuntimeError(f"GitHub did not finish uploading {asset_path.name}")
        except Exception as error:
            last_error = error
            if attempt == attempts:
                break
            print(
                f"Attempt {attempt} to publish {asset_path.name} failed; "
                f"retrying in {delay:g} seconds.",
                file=sys.stderr,
            )
            sleep(delay)
            delay *= 2

    raise RuntimeError(
        f"Unable to publish a verified {asset_path.name} after {attempts} attempts"
    ) from last_error


def reconcile_assets(
    repository: str,
    release_tag: str,
    asset_paths: Sequence[pathlib.Path],
) -> None:
    for asset_path in asset_paths:
        reconcile_asset(repository, release_tag, asset_path)
        print(f"Verified GitHub Release asset: {asset_path.name}")


def prune_assets(
    repository: str,
    release_tag: str,
    keep_names: set[str],
    run_github: GitHubCommand = run_github_command,
    sleep: Sleep = time.sleep,
    attempts: int = 6,
    initial_delay_seconds: float = 2,
) -> None:
    if attempts < 1:
        raise ValueError("attempts must be positive")
    if not keep_names:
        raise ValueError("keep_names must not be empty")

    delay = initial_delay_seconds
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            assets = release_assets(repository, release_tag, run_github)
            stale_assets = [
                asset for asset in assets if asset.get("name") not in keep_names
            ]
            if not stale_assets:
                return
            for remote_asset in stale_assets:
                run_github(
                    [
                        "api",
                        "--method",
                        "DELETE",
                        f"repos/{repository}/releases/assets/{remote_asset['id']}",
                    ]
                )
            remaining = release_assets(repository, release_tag, run_github)
            if all(asset.get("name") in keep_names for asset in remaining):
                return
            raise RuntimeError("GitHub still lists superseded release assets")
        except Exception as error:
            last_error = error
            if attempt == attempts:
                break
            print(
                f"Attempt {attempt} to prune {release_tag} failed; "
                f"retrying in {delay:g} seconds.",
                file=sys.stderr,
            )
            sleep(delay)
            delay *= 2

    raise RuntimeError(
        f"Unable to prune {release_tag} after {attempts} attempts"
    ) from last_error


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--asset", action="append", type=pathlib.Path, required=True)
    parser.add_argument("--prune-other-assets", action="store_true")
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    reconcile_assets(
        repository=arguments.repository,
        release_tag=arguments.release_tag,
        asset_paths=arguments.asset,
    )
    if arguments.prune_other_assets:
        prune_assets(
            repository=arguments.repository,
            release_tag=arguments.release_tag,
            keep_names={asset.name for asset in arguments.asset},
        )
        print(f"Removed superseded assets from {arguments.release_tag}")


if __name__ == "__main__":
    main()
