#!/usr/bin/env python3
"""Build a normalized root archive directly, including on case-insensitive macOS."""
import concurrent.futures
import copy
import hashlib
import gzip
import io
import json
from pathlib import Path
import sys
import tarfile
import urllib.request

HERE = Path(__file__).resolve().parent


def fetch(package, cache):
    path = cache / (package["sha256"] + ".archive")
    if not path.exists():
        temporary = path.with_suffix(".partial")
        with urllib.request.urlopen(package["url"], timeout=120) as response, temporary.open("wb") as output:
            while block := response.read(1024 * 1024):
                output.write(block)
        temporary.replace(path)
    digest = hashlib.file_digest(path.open("rb"), "sha256").hexdigest()
    if digest != package["sha256"] or path.stat().st_size != package["bytes"]:
        path.unlink()
        raise ValueError(f"Verification failed: {package['name']}")
    return path


def main():
    output = Path(sys.argv[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    cache = output.parent / "runtime-packages"
    cache.mkdir(exist_ok=True)
    lock = json.loads((HERE / "packages.lock.json").read_text())
    packages = lock["packages"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        paths = list(executor.map(lambda package: fetch(package, cache), packages))
    omarchy = json.loads((HERE / "omarchy.lock.json").read_text())
    omarchy_path = fetch(omarchy, cache)
    # Record the last owner of each path. Some Arch packages intentionally share directories.
    members, archives = {}, []
    try:
        for package, path in zip(packages, paths):
            archive = tarfile.open(path)
            archives.append(archive)
            for member in archive:
                name = member.name.removeprefix("./").rstrip("/")
                if not name or name.startswith(".") or name.startswith(("usr/include/", "usr/share/man/", "usr/share/info/")):
                    continue
                if member.ischr() or member.isblk() or member.isfifo():
                    continue
                members[name] = (archive, member)
        source = tarfile.open(omarchy_path)
        archives.append(source)
        for original in source:
            relative = original.name.split("/", 1)[-1].rstrip("/")
            if not original.isfile() or not relative.startswith(("bin/", "default/", "config/", "applications/", "themes/")):
                if relative not in ("LICENSE", "version") or not original.isfile():
                    continue
            if "/backgrounds/" in relative or relative.endswith((".mp4", ".png", ".jpg", ".webp")):
                continue
            member = copy.copy(original)
            member.name = "usr/share/omarchy/" + relative
            members[member.name] = (source, member)
        archive_path = output / "environment.tar.gzip"
        temporary = archive_path.with_suffix(".partial")
        with temporary.open("wb") as raw, gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=6, mtime=0) as compressed, tarfile.open(fileobj=compressed, mode="w") as tar:
            # Keep each compressed input sequential: global path sorting would repeatedly
            # rewind/decompress large package archives. Locked package/member order is stable.
            for archive in archives:
                for original in archive.getmembers():
                    name = original.name.removeprefix("./").rstrip("/")
                    if archive is source:
                        name = "usr/share/omarchy/" + original.name.split("/", 1)[-1].rstrip("/")
                        owned = members.get(name)
                        if owned is None:
                            continue
                        original = owned[1]
                    if members.get(name) != (archive, original):
                        continue
                    member = copy.copy(original)
                    member.name = name
                    member.uid = member.gid = member.mtime = 0
                    member.uname = member.gname = "root"
                    member.mode = 0o755 if member.isdir() or member.mode & 0o111 else 0o644
                    tar.addfile(member, archive.extractfile(original) if member.isfile() else None)
            provenance = json.dumps(lock, indent=2).encode()
            member = tarfile.TarInfo("usr/share/amarchy/packages.lock.json")
            member.size, member.mode = len(provenance), 0o644
            tar.addfile(member, io.BytesIO(provenance))
        temporary.replace(archive_path)
        (output / "environment.tar.xz").unlink(missing_ok=True)
        (output / "environment.tar.gz").unlink(missing_ok=True)
        metadata = {"version": "amarchy-omarchy-2", "sha256": hashlib.file_digest(archive_path.open("rb"), "sha256").hexdigest(),
                    "bytes": archive_path.stat().st_size, "expandedBytes": sum(m.size for _, m in members.values() if m.isfile())}
        (output / "environment.json").write_text(json.dumps(metadata) + "\n")
        print(json.dumps(metadata))
    finally:
        for archive in archives:
            archive.close()


if __name__ == "__main__":
    main()
