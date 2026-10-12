#!/usr/bin/env python3
"""Explicitly lock the complete upstream-derived ARM64 package closure."""
import argparse
import collections
import json
from pathlib import Path

from packages import catalog, name
from profile import inventory

HERE = Path(__file__).resolve().parent


def resolve(profile, available):
    providers = collections.defaultdict(set)
    for package, entry in available.items():
        for provided in entry.get("PROVIDES", []):
            providers[name(provided)].add(package)
    seeds = [item["package"] for item in profile["defaults"] if item["status"] == "planned"] + profile["hostPackages"]
    chosen, queue = {}, collections.deque(seeds)
    while queue:
        dependency = name(queue.popleft())
        package = dependency if dependency in available else profile["dependencyProviders"].get(dependency)
        candidates = providers[dependency]
        package = package or next((p for p in sorted(candidates) if p in seeds or p in chosen), None)
        if package is None and len(candidates) == 1:
            package = next(iter(candidates))
        if package is None or package not in available:
            raise ValueError(f"Choose a provider for {dependency}: {sorted(candidates)}")
        if package in chosen:
            continue
        chosen[package] = available[package]
        queue.extend(available[package].get("DEPENDS", []))
    return chosen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("databases", type=Path)
    arguments = parser.parse_args()
    profile = inventory(arguments.source, arguments.databases)
    policy = json.loads((HERE / "android-profile.json").read_text())
    available, databases = catalog(arguments.databases, policy["repositoryOverrides"])
    chosen = resolve(profile, available)
    lock = {"source": profile["source"], "databases": databases, "packages": []}
    for package, entry in sorted(chosen.items()):
        lock["packages"].append({
            "name": package, "version": entry["VERSION"][0],
            "url": entry["baseUrl"] + "/" + entry["FILENAME"][0],
            "bytes": int(entry["CSIZE"][0]), "installedBytes": int(entry["ISIZE"][0]), "sha256": entry["SHA256SUM"][0],
            "licenses": entry.get("LICENSE", []), "upstream": entry.get("URL", [""])[0],
            "base": entry.get("BASE", entry["NAME"])[0], "architecture": entry.get("ARCH", ["aarch64"])[0],
            "depends": entry.get("DEPENDS", []), "provides": entry.get("PROVIDES", []),
            "conflicts": entry.get("CONFLICTS", []), "replaces": entry.get("REPLACES", []),
        })
    (HERE / "profile.lock.json").write_text(json.dumps(profile, indent=2) + "\n")
    (HERE / "packages.lock.json").write_text(json.dumps(lock, indent=2) + "\n")
    print(f"Locked {len(chosen)} packages; {sum(p['bytes'] for p in lock['packages']) / 1048576:.1f} MiB compressed.")


if __name__ == "__main__":
    main()
