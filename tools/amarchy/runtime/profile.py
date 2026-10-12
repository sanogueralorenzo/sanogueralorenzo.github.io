#!/usr/bin/env python3
"""Inventory every pinned upstream default before resolving the Android package closure."""
import argparse
import hashlib
import json
from pathlib import Path
import tarfile

from packages import catalog

HERE = Path(__file__).resolve().parent


def inventory(source, databases):
    pin = json.loads((HERE / "omarchy.lock.json").read_text())
    if hashlib.file_digest(source.open("rb"), "sha256").hexdigest() != pin["sha256"]:
        raise ValueError("Omarchy source does not match the reviewed pin")
    policy = json.loads((HERE / "android-profile.json").read_text())
    available, provenance = catalog(databases, policy["repositoryOverrides"])
    with tarfile.open(source) as archive:
        prefix = "omarchy-" + pin["revision"] + "/install/"
        def names(list_name):
            text = archive.extractfile(prefix + "omarchy-" + list_name + ".packages").read().decode()
            return [name for line in text.splitlines() if (name := line.split("#", 1)[0].strip())]
        defaults = list(dict.fromkeys(names("base") + names("aarch64")))
        x86 = set(names("x86_64-only"))
    unknown = set(policy["omitted"]) - set(defaults)
    if unknown:
        raise ValueError(f"Omission policy no longer matches upstream: {sorted(unknown)}")
    result = {"source": pin, "databases": provenance, "defaults": [], "hostPackages": policy["hostPackages"], "dependencyProviders": policy["dependencyProviders"]}
    missing = []
    for requested in defaults:
        record = {"upstream": requested}
        if (requested in x86 and requested not in policy["architectureOverrides"]) or requested in policy["omitted"]:
            record.update(status="omitted", reason="Omitted by upstream's aarch64 package profile." if requested in x86 else policy["omitted"][requested])
        else:
            selected = policy["providers"].get(requested, requested)
            entry = available.get(selected)
            if entry is None:
                missing.append(selected)
                continue
            record.update(status="planned", package=selected, version=entry["VERSION"][0],
                          url=entry["baseUrl"] + "/" + entry["FILENAME"][0], sha256=entry["SHA256SUM"][0])
            if selected != requested:
                record["adaptation"] = f"ARM64 package provider: {requested} → {selected}."
            elif requested in policy["architectureOverrides"]:
                record["adaptation"] = policy["architectureOverrides"][requested]
            if requested in policy["repositoryReasons"]:
                record["adaptation"] = policy["repositoryReasons"][requested]
        result["defaults"].append(record)
    if missing:
        raise ValueError(f"Resolve these upstream defaults explicitly: {missing}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("databases", type=Path)
    arguments = parser.parse_args()
    result = inventory(arguments.source, arguments.databases)
    (HERE / "profile.lock.json").write_text(json.dumps(result, indent=2) + "\n")
    included = sum(item["status"] == "planned" for item in result["defaults"])
    print(f"Inventoried {len(result['defaults'])} upstream defaults: {included} planned, {len(result['defaults']) - included} explicit omissions.")


if __name__ == "__main__":
    main()
