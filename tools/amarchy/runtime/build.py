#!/usr/bin/env python3
"""Build a normalized root archive directly, including on case-insensitive macOS."""
import concurrent.futures
import copy
import hashlib
import gzip
import json
from pathlib import Path
import sys
import tarfile
import subprocess
from database import add_bytes, record, record_package

HERE = Path(__file__).resolve().parent


def fetch(package, cache):
    path = cache / (package["sha256"] + ".archive")
    if not path.exists():
        temporary = path.with_suffix(".partial")
        subprocess.run(["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "2", "--max-time", "180", package["url"], "--output", str(temporary)], check=True)
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
    provenance_inputs = {filename: (HERE / filename).read_bytes() for filename in ("packages.lock.json", "omarchy.lock.json", "profile.lock.json", "android-profile.json")}
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
                if not name or name.startswith("."):
                    continue
                if member.ischr() or member.isblk() or member.isfifo():
                    continue
                members[name] = (archive, member)
        source = tarfile.open(omarchy_path)
        archives.append(source)
        source_aliases, changed = {}, {}
        for original in source:
            relative = original.name.removeprefix("omarchy-" + omarchy["revision"]).lstrip("/").rstrip("/")
            if not relative or not (original.isfile() or original.isdir() or original.issym()):
                continue
            destinations = ["usr/share/omarchy/" + relative]
            if relative.startswith("config/"):
                destinations.append("etc/skel/.config/" + relative.removeprefix("config/"))
            elif relative.startswith("applications/") and relative.endswith(".desktop") and "/icons/" not in relative:
                destinations.append("etc/skel/.local/share/applications/" + relative.split("/")[-1])
            elif relative == "default/bashrc":
                destinations.append("etc/skel/.bashrc")
            elif relative.startswith("default/nautilus-python/extensions/"):
                destinations.append("etc/skel/.local/share/nautilus-python/extensions/" + relative.split("/")[-1])
            elif relative == "default/hypr/toggles/flags.lua":
                destinations.append("etc/skel/.local/state/omarchy/toggles/hypr/flags.lua")
            elif relative == "default/fonts/omarchy/omarchy.ttf":
                destinations.append("usr/share/fonts/omarchy/omarchy.ttf")
            elif relative == "default/fontconfig/conf.avail/50-omarchy.conf":
                destinations.append("etc/fonts/conf.d/50-omarchy.conf")
            elif relative == "default/xdg-terminal-exec/hyprland-xdg-terminals.list":
                destinations.append("usr/share/xdg-terminal-exec/hyprland-xdg-terminals.list")
            elif relative == "default/applications/mimeapps.list":
                destinations.append("usr/share/applications/mimeapps.list")
            source_aliases[original.name] = destinations
            for destination in destinations:
                member = copy.copy(original)
                member.name = destination
                replacements = {
                    "bin/omarchy-launch-shell": (b"systemd-cat -t omarchy-shell -- quickshell", b"quickshell"),
                    "bin/omarchy-launch-browser": (
                        b'systemd-run --user --quiet --collect --unit="omarchy-browser-$(date +%s%N)" \\\n    --property=StandardOutput=null --property=StandardError=null \\\n    uwsm-app -- "$browser_exec" "${@/--private/$private_flag}"',
                        b'setsid uwsm-app -- "$browser_exec" "${@/--private/$private_flag}" >/dev/null 2>&1 &'),
                    "bin/omarchy-theme-set": (
                        b'run_parallel() {\n  local pid\n  local pids=()\n\n  for command in "$@"; do\n    bash -lc "$command" &\n    pids+=("$!")\n  done\n\n  for pid in "${pids[@]}"; do\n    wait "$pid"\n  done\n}',
                        b'run_parallel() {\n  # Android limits unregistered child processes; serialize app-retint hooks.\n  for command in "$@"; do\n    bash -lc "$command"\n  done\n}'),
                }
                if relative in replacements:
                    data = source.extractfile(original).read()
                    previous, replacement = replacements[relative]
                    if data.count(previous) != 1:
                        raise ValueError(f"Upstream launcher no longer matches the Android adaptation: {relative}")
                    changed[destination] = data.replace(previous, replacement)
                    member.size = len(changed[destination])
                members[destination] = (source, member)
        archive_path = output / "environment.tar.gzip"
        temporary = archive_path.with_suffix(".partial")
        extra_bytes = 0
        with temporary.open("wb") as raw, gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=6, mtime=0) as compressed, tarfile.open(fileobj=compressed, mode="w") as tar:
            # Keep each compressed input sequential: global path sorting would repeatedly
            # rewind/decompress large package archives. Locked package/member order is stable.
            for archive in archives:
                for original in archive.getmembers():
                    destinations = source_aliases.get(original.name, []) if archive is source else [original.name.removeprefix("./").rstrip("/")]
                    for name in destinations:
                        owned = members.get(name)
                        if owned is None or owned[0] is not archive or (archive is not source and owned[1] is not original):
                            continue
                        member = copy.copy(owned[1])
                        member.name = name
                        member.uid = member.gid = member.mtime = 0
                        member.uname = member.gname = "root"
                        member.mode = 0o755 if member.isdir() or member.mode & 0o111 else 0o644
                        if name in changed:
                            add_bytes(tar, name, changed[name], member.mode)
                        else:
                            tar.addfile(member, archive.extractfile(original) if member.isfile() else None)
                if archive is not source:
                    extra_bytes += record_package(tar, packages[archives.index(archive)], archive)
            source_version = source.extractfile("omarchy-" + omarchy["revision"] + "/version").read().decode().strip()
            source_package = {"name": "omarchy", "version": source_version + "-1", "architecture": "aarch64",
                "upstream": "https://github.com/omacom/omarchy", "installedBytes": sum(member.size for owner, member in members.values() if owner is source and member.isfile()),
                "licenses": ["MIT"], "depends": [], "provides": [], "conflicts": [], "replaces": []}
            extra_bytes += record(tar, source_package, {name for name, (owner, _) in members.items() if owner is source and name.startswith("usr/share/omarchy/")},
                "Upstream Omarchy " + omarchy["revision"] + ", bundled by Amarchy")
            extra_bytes += add_bytes(tar, "var/lib/pacman/local/ALPM_DB_VERSION", b"9\n")
            for path in sorted((HERE / "android-overlay").rglob("*")):
                if path.is_file():
                    extra_bytes += add_bytes(tar, path.relative_to(HERE / "android-overlay").as_posix(), path.read_bytes(), 0o755)
            for filename in ("packages.lock.json", "omarchy.lock.json", "profile.lock.json", "android-profile.json"):
                extra_bytes += add_bytes(tar, "usr/share/amarchy/" + filename, provenance_inputs[filename])
        temporary.replace(archive_path)
        (output / "environment.tar.xz").unlink(missing_ok=True)
        (output / "environment.tar.gz").unlink(missing_ok=True)
        metadata = {"version": "amarchy-upstream-3", "sha256": hashlib.file_digest(archive_path.open("rb"), "sha256").hexdigest(),
                    "bytes": archive_path.stat().st_size, "expandedBytes": extra_bytes + sum(m.size for _, m in members.values() if m.isfile())}
        (output / "environment.json").write_text(json.dumps(metadata) + "\n")
        print(json.dumps(metadata))
    finally:
        for archive in archives:
            archive.close()


if __name__ == "__main__":
    main()
