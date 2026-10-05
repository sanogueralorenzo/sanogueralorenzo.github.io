#!/usr/bin/env python3
"""Refresh the Arch ARM package lock; builds consume only this reviewed lock."""
import collections
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import urllib.parse
import tarfile
import urllib.request

HERE = Path(__file__).resolve().parent
MIRROR = "https://ca.us.mirror.archlinuxarm.org/aarch64"


def fields(data):
    result = {}
    key = None
    for line in data.decode().splitlines():
        if line.startswith("%") and line.endswith("%"):
            key = line.strip("%")
            result[key] = []
        elif key and line:
            result[key].append(line)
    return result


def name(dependency):
    return re.split(r"[<>=]", dependency, maxsplit=1)[0]


def runtime_dependencies(package, dependencies, custom_mesa=True):
    unused = set()
    if package == "pulseaudio":
        # Only the native UNIX protocol and PCM pipe sink are configured.
        unused = {"systemd", "rtkit", "fftw", "webrtc-audio-processing-1"}
    elif package == "mesa" and custom_mesa:
        # mesa/build.sh builds only Zink, with LLVM, sensors and SPIR-V
        # diagnostic tools disabled. Keep the other upstream dependencies.
        unused = {"llvm-libs", "lm_sensors", "spirv-tools"}
    return [dependency for dependency in dependencies if name(dependency) not in unused]


def source_lock(packages):
    previous = {base: (version, url) for base, version, url in
                (line.split("\t") for line in (HERE / "sources.tsv").read_text().splitlines())}
    bases = {entry.get("BASE", entry["NAME"])[0]: entry for entry in packages.values()
             if any("GPL" in license for license in entry.get("LICENSE", []))}
    rows = []
    for base, entry in sorted(bases.items()):
        version = entry["VERSION"][0]
        old_version, url = previous.get(base, (None, ""))
        if version != old_version:
            if url.startswith("https://github.com/archlinuxarm/PKGBUILDs/tree/"):
                path = "/".join(url.split("/")[7:]) + "/PKGBUILD"
                query = urllib.parse.urlencode({"path": path, "per_page": 100})
                request = urllib.request.Request(f"https://api.github.com/repos/archlinuxarm/PKGBUILDs/commits?{query}",
                                                 headers={"User-Agent": "AndroidSteam-runtime"})
                with urllib.request.urlopen(request, timeout=60) as response:
                    commits = json.loads(response.read(2 * 1024 * 1024))
                match = next((commit for commit in commits if commit["commit"]["message"].splitlines()[0]
                              .endswith(" to " + version.split(":")[-1])), None)
                if match is None:
                    raise ValueError(f"Pin the exact ARM packaging recipe for {base} {version} in sources.tsv")
                url = f'https://github.com/archlinuxarm/PKGBUILDs/tree/{match["sha"]}/{path.rsplit("/", 1)[0]}'
            else:
                repo = f"https://gitlab.archlinux.org/archlinux/packaging/packages/{base}"
                tag = version.replace(":", "-")
                refs = subprocess.check_output(["git", "ls-remote", repo + ".git", "refs/tags/" + tag,
                                                "refs/tags/" + tag + "^{}"], text=True, timeout=60).splitlines()
                if not refs:
                    raise ValueError(f"Pin the exact upstream packaging recipe for {base} {version} in sources.tsv")
                url = f'{repo}/-/tree/{refs[-1].split()[0]}'
        rows.append("\t".join((base, version, url)))
    return "\n".join(rows) + "\n"


def main():
    packages = {}
    databases = []
    for repo in ("core", "extra"):
        url = f"{MIRROR}/{repo}/{repo}.db"
        with urllib.request.urlopen(url, timeout=60) as response:
            data = response.read(32 * 1024 * 1024 + 1)
        if len(data) > 32 * 1024 * 1024:
            raise ValueError("Repository database exceeds its limit")
        databases.append(f"{repo}\t{hashlib.sha256(data).hexdigest()}")
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            entries = {}
            for item in archive:
                if item.name.endswith(("/desc", "/depends")):
                    entries.setdefault(item.name.split("/")[0], {}).update(fields(archive.extractfile(item).read()))
        for entry in entries.values():
            if "NAME" in entry:
                entry["repository"] = repo
                packages[entry["NAME"][0]] = entry
    providers = collections.defaultdict(list)
    for package, entry in packages.items():
        for provided in entry.get("PROVIDES", []):
            providers[name(provided)].append(package)
    seeds = [line.strip() for line in (HERE / "seeds.txt").read_text().splitlines()
             if line.strip() and not line.startswith("#")]
    # Keep the GL dispatch implementation explicit; never pick an arbitrary GPU provider.
    preferred = {"libgl": "libglvnd", "libegl": "libglvnd", "libgles": "libglvnd", "libjack.so": "pipewire-jack"}
    chosen = {}
    queue = collections.deque(seeds)
    while queue:
        dependency = name(queue.popleft())
        candidates = providers[dependency]
        package = dependency if dependency in packages else preferred.get(dependency)
        package = package or next((p for p in candidates if p in seeds or p in chosen), None)
        if package is None and len(candidates) == 1:
            package = candidates[0]
        if package is None:
            raise ValueError(f"Choose a provider for {dependency}: {candidates}")
        if package in chosen:
            continue
        entry = packages[package]
        chosen[package] = entry
        queue.extend(runtime_dependencies(package, entry.get("DEPENDS", [])))
    rows = []
    for package, entry in sorted(chosen.items()):
        rows.append("\t".join((package, entry["VERSION"][0],
                               f'{entry["repository"]}/{entry["FILENAME"][0]}',
                               entry["CSIZE"][0], entry["SHA256SUM"][0])))
    sources = source_lock(chosen)
    (HERE / "packages.tsv").write_text("\n".join(rows) + "\n")
    (HERE / "repositories.tsv").write_text("\n".join(databases) + "\n")
    (HERE / "sources.tsv").write_text(sources)
    print(f"Locked {len(rows)} packages; review the diff, build, and validate on the S24 before publishing.")


if __name__ == "__main__":
    main()
