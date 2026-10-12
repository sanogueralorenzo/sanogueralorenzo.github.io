#!/usr/bin/env python3
"""Explicitly refresh the reviewed ARM64 package closure; never run during builds."""
import collections
import hashlib
import io
import json
from pathlib import Path
import re
import tarfile
import urllib.request

HERE = Path(__file__).resolve().parent
MIRROR = "https://ca.us.mirror.archlinuxarm.org/aarch64"


def fields(data):
    result, key = {}, None
    for line in data.decode().splitlines():
        if line.startswith("%") and line.endswith("%"):
            key = line.strip("%")
            result[key] = []
        elif key and line:
            result[key].append(line)
    return result


def name(dependency):
    return re.split(r"[<>=]", dependency, maxsplit=1)[0]


def main():
    packages, databases = {}, {}
    for repository in ("core", "extra"):
        url = f"{MIRROR}/{repository}/{repository}.db"
        with urllib.request.urlopen(url, timeout=60) as response:
            data = response.read(32 * 1024 * 1024 + 1)
        if len(data) > 32 * 1024 * 1024:
            raise ValueError("Repository database exceeds its limit")
        databases[url] = hashlib.sha256(data).hexdigest()
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            entries = {}
            for item in archive:
                if item.name.endswith(("/desc", "/depends")):
                    entries.setdefault(item.name.split("/")[0], {}).update(fields(archive.extractfile(item).read()))
        for entry in entries.values():
            if "NAME" in entry:
                entry["repository"] = repository
                packages[entry["NAME"][0]] = entry
    providers = collections.defaultdict(list)
    for package, entry in packages.items():
        for provided in entry.get("PROVIDES", []):
            providers[name(provided)].append(package)
    seeds = [line for line in (HERE / "seeds.txt").read_text().splitlines() if line and not line.startswith("#")]
    preferred = {"libgl": "libglvnd", "libegl": "libglvnd", "libgles": "libglvnd", "libjack.so": "pipewire-jack"}
    chosen, queue = {}, collections.deque(seeds)
    while queue:
        dependency = name(queue.popleft())
        package = dependency if dependency in packages else preferred.get(dependency)
        candidates = providers[dependency]
        package = package or next((p for p in candidates if p in seeds or p in chosen), None)
        if package is None and len(candidates) == 1:
            package = candidates[0]
        if package is None:
            raise ValueError(f"Choose a provider for {dependency}: {candidates}")
        if package in chosen:
            continue
        chosen[package] = packages[package]
        queue.extend(packages[package].get("DEPENDS", []))
    lock = {"databases": databases, "packages": []}
    for package, entry in sorted(chosen.items()):
        lock["packages"].append({
            "name": package, "version": entry["VERSION"][0],
            "url": f'{MIRROR}/{entry["repository"]}/{entry["FILENAME"][0]}',
            "bytes": int(entry["CSIZE"][0]), "sha256": entry["SHA256SUM"][0],
            "licenses": entry.get("LICENSE", []), "upstream": entry.get("URL", [""])[0],
            "base": entry.get("BASE", entry["NAME"])[0],
        })
    (HERE / "packages.lock.json").write_text(json.dumps(lock, indent=2) + "\n")
    print(f"Locked {len(chosen)} packages; {sum(p['bytes'] for p in lock['packages']) / 1048576:.1f} MiB compressed.")


if __name__ == "__main__":
    main()

