#!/usr/bin/env python3
"""Report a built root's sizes, dependency paths and Steam-library overlap; remove nothing."""
import argparse
import collections
import gzip
import json
from pathlib import Path
import re
import tarfile
from update import runtime_dependencies

HERE = Path(__file__).resolve().parent


def package_metadata(archive):
    metadata = collections.defaultdict(list)
    paths = []
    found = set()
    with tarfile.open(archive, mode="r|*") as contents:
        for item in contents:
            if item.name == ".PKGINFO":
                for line in contents.extractfile(item).read().decode().splitlines():
                    if " = " in line:
                        key, value = line.split(" = ", 1)
                        metadata[key].append(value)
                found.add(item.name)
            elif item.name == ".MTREE":
                for line in gzip.decompress(contents.extractfile(item).read()).decode().splitlines():
                    if line.startswith("./"):
                        path = line.split(" ", 1)[0][2:]
                        paths.append(re.sub(r"\\([0-7]{3})", lambda m: chr(int(m[1], 8)), path))
                found.add(item.name)
            if len(found) == 2:
                break
    if len(found) != 2:
        raise ValueError(f"Package lacks its metadata: {archive}")
    return dict(metadata), paths


def dependency_paths(packages, seeds, custom_mesa=False):
    providers = collections.defaultdict(list)
    for package, entry in packages.items():
        for provided in entry.get("provides", []):
            providers[re.split(r"[<>=]", provided, maxsplit=1)[0]].append(package)
    preferred = {"libgl": "libglvnd", "libegl": "libglvnd", "libgles": "libglvnd", "libjack.so": "pipewire-jack"}
    def resolve(dependency):
        name = re.split(r"[<>=]", dependency, maxsplit=1)[0]
        candidates = providers[name]
        package = name if name in packages else preferred.get(name)
        if package is None and len(candidates) == 1:
            package = candidates[0]
        if package not in packages:
            raise ValueError(f"Unresolved dependency {dependency}: {candidates}")
        return package

    paths = {resolve(seed): [resolve(seed)] for seed in seeds}
    queue = collections.deque(paths)
    while queue:
        parent = queue.popleft()
        for dependency in runtime_dependencies(parent, packages[parent].get("depend", []), custom_mesa):
            child = resolve(dependency)
            if child not in paths:
                paths[child] = paths[parent] + [child]
                queue.append(child)
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="Extracted built root on a case-sensitive filesystem")
    parser.add_argument("cache", type=Path, help="Checksum-addressed package cache from build.sh")
    parser.add_argument("--steam-files", type=Path, help="File names from Steam's ARM64 binary/library directories only")
    args = parser.parse_args()
    root = args.root.resolve()
    sizes = {str(path.relative_to(root)): path.stat().st_size for path in root.rglob("*")
             if path.is_file() and not path.is_symlink()}
    rows = [line.split("\t") for line in (root / "usr/share/androidsteam/packages.tsv").read_text().splitlines()]
    seeds = [line for line in (root / "usr/share/androidsteam/seeds.txt").read_text().splitlines()
             if line and not line.startswith("#")]
    metadata = {}
    reports = []
    mesa_files = root / "usr/share/androidsteam/mesa/installed-files.txt"
    for name, version, url, download, checksum in rows:
        entry, files = package_metadata(args.cache / f"{checksum}.pkg.tar.xz")
        if entry["pkgname"] != [name] or entry["pkgver"] != [version]:
            raise ValueError(f"Cache metadata does not match lock: {name}")
        metadata[name] = entry
        if name == "mesa" and mesa_files.is_file():
            files = mesa_files.read_text().splitlines()
        retained = sum(sizes.get(path, 0) for path in files)
        reports.append({"name": name, "version": version, "download_bytes": int(download),
                        "upstream_installed_bytes": int(entry["size"][0]), "retained_bytes": retained})
    paths = dependency_paths(metadata, seeds, mesa_files.is_file())
    for package in reports:
        package["dependency_path"] = paths.get(package["name"], [])
    directories = collections.Counter()
    for name, size in sizes.items():
        directories["/".join(name.split("/")[:3])] += size
    steam = {Path(line).name for line in args.steam_files.read_text().splitlines()} if args.steam_files else set()
    overlap = [{"path": name, "bytes": size} for name, size in sizes.items()
               if Path(name).name in steam and ".so" in Path(name).name]
    print(json.dumps({"package_count": len(rows), "package_download_bytes": sum(int(row[3]) for row in rows),
                      "installed_file_bytes": sum(sizes.values()),
                      "largest_directories": directories.most_common(30),
                      "largest_files": sorted(sizes.items(), key=lambda item: item[1], reverse=True)[:30],
                      "packages": sorted(reports, key=lambda package: package["retained_bytes"], reverse=True),
                      "steam_name_overlap": overlap,
                      "overlap_limit": "Name overlap is a candidate for investigation, not ABI compatibility or proof of safe removal."}, indent=2))


if __name__ == "__main__":
    main()
