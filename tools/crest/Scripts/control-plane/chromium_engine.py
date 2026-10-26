#!/usr/bin/env python3
"""Identify the prebuilt Chromium engine a Crest source tree needs.

The engine — Chromium with Crest's host patch and overlay compiled in — takes
hours to build and cannot be built on a hosted runner, so releases download a
prebuilt engine published once per engine revision. Its key hashes every input
that is compiled into the engine: the pinned source lock, the host patch and
its reviewed input hashes, the overlay sources, the host header and the
engine contract headers copied into the tree, and the scripts that prepare,
configure and build it. Anything else
— the Swift UI framework, the native core, packaging — is built per release.
"""
import argparse
import hashlib
from pathlib import Path

INPUTS = (
    "CrestEngines/Chromium/source.lock.json",
    "CrestEngines/Chromium/host-inputs.json",
    "CrestEngines/Chromium/Patches",
    "CrestEngines/Chromium/Overlay",
    "CrestEngines/Chromium/Apple/CrestChromiumHost.h",
    "CrestContracts/include/crest_core.h",
    "CrestContracts/include/crest_app.h",
    "CrestContracts/include/crest_engine.h",
    "CrestContracts/include/crest_engine_contract.h",
    "Scripts/control-plane/prepare-chromium.py",
    "Scripts/control-plane/apply-chromium-host.py",
    "Scripts/control-plane/configure-chromium.py",
    "Scripts/control-plane/build-chromium-baseline.py",
)


def engine_key(repo: Path) -> str:
    digest = hashlib.sha256()
    for name in INPUTS:
        path = repo / name
        files = sorted(p for p in path.rglob("*") if p.is_file()) if path.is_dir() else [path]
        if not files or not all(p.is_file() for p in files):
            raise SystemExit(f"Missing engine input: {name}")
        for file in files:
            relative = file.relative_to(repo).as_posix()
            digest.update(relative.encode() + b"\0")
            digest.update(hashlib.sha256(file.read_bytes()).hexdigest().encode() + b"\n")
    return digest.hexdigest()


def release_tag(key: str) -> str:
    return f"chromium-engine-{key[:16]}"


def asset_name(key: str) -> str:
    return f"Crest-Chromium-Engine-{key[:16]}-arm64.zip"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("field", choices=["key", "tag", "asset"])
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    key = engine_key(args.repo.resolve())
    print({"key": key, "tag": release_tag(key), "asset": asset_name(key)}[args.field])


if __name__ == "__main__":
    main()
