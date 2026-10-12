"""Reviewed repository metadata shared by profile inventory and closure locking."""
import hashlib
import re
import tarfile

REPOSITORIES = {
    "core": "https://ca.us.mirror.archlinuxarm.org/aarch64/core",
    "extra": "https://ca.us.mirror.archlinuxarm.org/aarch64/extra",
    "stable": "https://pkgs.omarchy.org/stable/aarch64",
    "edge": "https://pkgs.omarchy.org/edge/aarch64",
}


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


def catalog(databases, overrides):
    packages, provenance = {}, {}
    for repository, base in REPOSITORIES.items():
        path = databases / (repository + ".db")
        if path.stat().st_size > 32 * 1024 * 1024:
            raise ValueError("Repository database exceeds its limit")
        url = base + "/" + ("omarchy" if repository in ("stable", "edge") else repository) + ".db"
        provenance[url] = hashlib.file_digest(path.open("rb"), "sha256").hexdigest()
        with tarfile.open(path) as archive:
            entries = {}
            for member in archive:
                if member.name.endswith(("/desc", "/depends")):
                    entries.setdefault(member.name.split("/")[0], {}).update(fields(archive.extractfile(member).read()))
            for entry in entries.values():
                if "NAME" in entry:
                    entry["repository"] = repository
                    entry["baseUrl"] = base
                    package = entry["NAME"][0]
                    if package not in packages or overrides.get(package) == repository:
                        packages[package] = entry
    for package, repository in overrides.items():
        if packages.get(package, {}).get("repository") != repository:
            raise ValueError(f"Required package repository unavailable: {package} from {repository}")
    return packages, provenance
